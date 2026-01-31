# PostgreSQL Exporter - Prometheus metrics for PostgreSQL/Patroni/Citus
# Exposes metrics on port 9187 for scraping by Prometheus/VictoriaMetrics
#
# Metrics include:
# - PostgreSQL: connections, transactions, locks, replication lag
# - Citus: distributed queries, shard stats, node health
# - Custom: uptrack-specific queries
#
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # All Patroni nodes run the exporter
  patroniNodes = [ "nbg1" "nbg2" "nbg3" "nbg4" ];
  isExporterNode = builtins.elem nodeName patroniNodes;

  # Custom queries for Citus and application metrics
  customQueries = pkgs.writeText "postgres-exporter-queries.yaml" ''
    # Citus cluster health
    citus_worker_nodes:
      query: "SELECT nodename, nodeport, isactive::int as is_active FROM pg_dist_node"
      metrics:
        - nodename:
            usage: "LABEL"
            description: "Worker node hostname"
        - nodeport:
            usage: "LABEL"
            description: "Worker node port"
        - is_active:
            usage: "GAUGE"
            description: "Whether the worker node is active"

    # Citus shard count per table
    citus_shard_count:
      query: |
        SELECT logicalrelid::text as table_name, count(*) as shard_count
        FROM pg_dist_shard
        GROUP BY logicalrelid
      metrics:
        - table_name:
            usage: "LABEL"
            description: "Distributed table name"
        - shard_count:
            usage: "GAUGE"
            description: "Number of shards for this table"

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
  services.prometheus.exporters.postgres = {
    enable = true;
    port = 9187;

    # Connect to local Patroni-managed PostgreSQL
    dataSourceName = "postgresql:///postgres?host=/run/patroni&user=postgres";

    # Use custom queries for Citus metrics
    extraFlags = [
      "--extend.query-path=${customQueries}"
      "--auto-discover-databases"
    ];

    # Run as postgres user to access socket
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
