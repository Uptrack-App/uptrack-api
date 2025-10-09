# ClickHouse - Time-series analytics database
# Only runs on Node C
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;
  isClickHouseNode = nodeName == "uptrack-node-c";

  nodeCTailscaleIP = "100.64.0.3";  # Replace after setup

in lib.mkIf isClickHouseNode {
  services.clickhouse = {
    enable = true;

    # Listen on Tailscale IP + localhost
    listenHost = nodeCTailscaleIP;

    # Basic configuration
    settings = {
      # Logging
      log_level = "information";

      # Performance
      max_memory_usage = 10737418240;  # 10GB
      max_concurrent_queries = 100;

      # Storage
      max_table_size_to_drop = 0;
      max_partition_size_to_drop = 0;
    };
  };

  # Create ClickHouse monitoring tables
  systemd.services.clickhouse-init-schema = {
    description = "Initialize ClickHouse schema for Uptrack";
    after = [ "clickhouse.service" ];
    requires = [ "clickhouse.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "clickhouse";
      ExecStart = pkgs.writeShellScript "clickhouse-init" ''
        # Wait for ClickHouse to be ready
        until ${pkgs.clickhouse}/bin/clickhouse-client --query="SELECT 1" &>/dev/null; do
          echo "Waiting for ClickHouse..."
          sleep 2
        done

        # Create checks_raw table
        ${pkgs.clickhouse}/bin/clickhouse-client --multiquery <<'EOF'
        CREATE TABLE IF NOT EXISTS checks_raw (
          timestamp DateTime64(3),
          monitor_id UUID,
          status String,
          response_time_ms UInt32,
          region String,
          status_code Nullable(UInt16),
          error_message Nullable(String)
        ) ENGINE = MergeTree()
        PARTITION BY toYYYYMM(timestamp)
        ORDER BY (monitor_id, timestamp);

        CREATE MATERIALIZED VIEW IF NOT EXISTS checks_1h_rollup
        ENGINE = SummingMergeTree()
        PARTITION BY toYYYYMM(timestamp)
        ORDER BY (monitor_id, toStartOfHour(timestamp))
        AS SELECT
          toStartOfHour(timestamp) as timestamp,
          monitor_id,
          region,
          count() as check_count,
          avg(response_time_ms) as avg_response_time,
          sum(status = 'up') as success_count
        FROM checks_raw
        GROUP BY monitor_id, region, toStartOfHour(timestamp);
        EOF

        echo "ClickHouse schema initialized"
      '';
    };
  };

  # Daily backup
  systemd.services.clickhouse-backup = {
    description = "ClickHouse backup service";
    serviceConfig = {
      Type = "oneshot";
      User = "clickhouse";
      ExecStart = pkgs.writeShellScript "backup-clickhouse" ''
        BACKUP_DIR="/var/backup/clickhouse"
        mkdir -p "$BACKUP_DIR"

        ${pkgs.clickhouse}/bin/clickhouse-client --query="BACKUP DATABASE default TO Disk('backups', 'backup-$(date +%Y%m%d).zip')"

        # Keep only last 7 days of backups
        find "$BACKUP_DIR" -type f -mtime +7 -delete
      '';
    };
  };

  systemd.timers.clickhouse-backup = {
    description = "Daily ClickHouse backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";  # 3 AM
      Persistent = true;
    };
  };

  # Create backup directory
  systemd.tmpfiles.rules = [
    "d /var/backup/clickhouse 0750 clickhouse clickhouse -"
  ];

  # No public firewall rules - accessed via Tailscale only
}
