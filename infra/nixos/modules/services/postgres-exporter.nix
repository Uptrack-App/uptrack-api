# PostgreSQL Exporter - Prometheus metrics for PostgreSQL/Patroni
# Exposes metrics on port 9187 for scraping by VictoriaMetrics
#
# Metrics include:
# - PostgreSQL: connections, transactions, locks, replication lag
# - Patroni: replication lag between primary and replicas
# - Custom: table sizes for capacity planning
#
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Tailscale IPs (must match patroni.nix)
  nodes = {
    nbg1 = "100.64.1.1";
    nbg2 = "100.64.1.2";
    nbg3 = "100.117.191.50";
    nbg4 = "100.72.224.65";
  };

  nodeIP = if builtins.hasAttr nodeName nodes then nodes.${nodeName} else "127.0.0.1";

  # All Patroni nodes run the exporter
  patroniNodes = [ "nbg1" "nbg2" "nbg3" "nbg4" ];
  isExporterNode = builtins.elem nodeName patroniNodes;

  # Custom queries for PostgreSQL metrics
  customQueries = pkgs.writeText "postgres-exporter-queries.yaml" ''
    # Patroni replication status
    patroni_replication_lag:
      query: |
        SELECT
          client_addr,
          EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::float as lag_seconds
        FROM pg_stat_replication
        WHERE state = 'streaming'
      metrics:
        - client_addr:
            usage: "LABEL"
            description: "Replica address"
        - lag_seconds:
            usage: "GAUGE"
            description: "Replication lag in seconds"

    # Connection stats by database
    pg_database_connections:
      query: |
        SELECT datname, count(*) as connections
        FROM pg_stat_activity
        WHERE datname IS NOT NULL
        GROUP BY datname
      metrics:
        - datname:
            usage: "LABEL"
            description: "Database name"
        - connections:
            usage: "GAUGE"
            description: "Number of connections"

    # Transaction stats
    pg_stat_database_transactions:
      query: |
        SELECT datname, xact_commit, xact_rollback, blks_read, blks_hit
        FROM pg_stat_database
        WHERE datname IS NOT NULL
      metrics:
        - datname:
            usage: "LABEL"
            description: "Database name"
        - xact_commit:
            usage: "COUNTER"
            description: "Transactions committed"
        - xact_rollback:
            usage: "COUNTER"
            description: "Transactions rolled back"
        - blks_read:
            usage: "COUNTER"
            description: "Blocks read from disk"
        - blks_hit:
            usage: "COUNTER"
            description: "Blocks hit in cache"

    # Table sizes for capacity planning
    pg_table_sizes:
      query: |
        SELECT
          schemaname,
          relname as table_name,
          pg_total_relation_size(schemaname || '.' || relname)::float as total_bytes
        FROM pg_stat_user_tables
        WHERE schemaname = 'app'
        ORDER BY total_bytes DESC
        LIMIT 20
      metrics:
        - schemaname:
            usage: "LABEL"
            description: "Schema name"
        - table_name:
            usage: "LABEL"
            description: "Table name"
        - total_bytes:
            usage: "GAUGE"
            description: "Total table size in bytes"
  '';

in lib.mkIf isExporterNode {
  # Create postgres user/group for exporter (Patroni manages its own postgres)
  users.users.postgres = {
    isSystemUser = true;
    group = "postgres";
    description = "PostgreSQL server user";
  };
  users.groups.postgres = {};

  # PostgreSQL exporter service
  # Patroni runs PostgreSQL listening on the Tailscale IP only (no Unix socket).
  # We connect via TCP with peer auth disabled (Patroni pg_hba allows local trust).
  services.prometheus.exporters.postgres = {
    enable = true;
    port = 9187;

    # Connect via TCP to Patroni-managed PostgreSQL on Tailscale IP
    dataSourceName = "postgresql://postgres@${nodeIP}:5432/postgres?sslmode=disable";

    # Use custom queries for additional metrics
    extraFlags = [
      "--extend.query-path=${customQueries}"
    ];

    # Run as postgres user
    user = "postgres";
    group = "postgres";
  };

  # Ensure exporter starts after Patroni
  systemd.services.prometheus-postgres-exporter = {
    after = [ "patroni.service" ];
    wants = [ "patroni.service" ];

    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 10;
    };
  };

  # Open firewall for metrics scraping (Tailscale only)
  networking.firewall.allowedTCPPorts = [ 9187 ];
}
