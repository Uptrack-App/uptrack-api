# Patroni - PostgreSQL High Availability with automatic failover
# Only runs on Node A and Node B
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Tailscale IPs (replace after setup)
  nodeATailscaleIP = "100.64.0.1";
  nodeBTailscaleIP = "100.64.0.2";
  nodeCTailscaleIP = "100.64.0.3";

  nodeIP = if nodeName == "uptrack-node-a" then nodeATailscaleIP
           else nodeBTailscaleIP;

  # Patroni only runs on Node A and B
  isPostgresNode = nodeName == "uptrack-node-a" || nodeName == "uptrack-node-b";

in lib.mkIf isPostgresNode {
  # PostgreSQL 16 (TimescaleDB removed - using ClickHouse for time-series)
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    # Patroni will manage the cluster, so don't auto-start
    enableTCPIP = true;
    port = 5432;

    # Basic performance settings
    settings = {
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      maintenance_work_mem = "64MB";
      work_mem = "4MB";
      max_connections = 100;
    };
  };

  # Patroni for HA
  services.patroni = {
    enable = true;
    name = nodeName;

    scope = "uptrack-pg-cluster";
    namespace = "/service/";

    # Patroni REST API
    restApi = {
      listen = "0.0.0.0:8008";
      connect = "${nodeIP}:8008";
    };

    # etcd endpoints
    etcd = {
      hosts = [
        "${nodeATailscaleIP}:2379"
        "${nodeBTailscaleIP}:2379"
        "${nodeCTailscaleIP}:2379"
      ];
    };

    # PostgreSQL configuration
    postgresql = {
      listen = "${nodeIP}:5432,127.0.0.1:5432";
      connect_address = "${nodeIP}:5432";
      data_dir = "/var/lib/postgresql/16";
      bin_dir = "${pkgs.postgresql_16}/bin";

      authentication = {
        replication = {
          username = "replicator";
          password = "CHANGE_ME_REPLICATOR_PASSWORD";
        };
        superuser = {
          username = "postgres";
          password = "CHANGE_ME_POSTGRES_PASSWORD";
        };
      };

      parameters = {
        unix_socket_directories = "/run/postgresql";
        wal_level = "replica";
        max_wal_senders = 10;
        max_replication_slots = 10;
        hot_standby = "on";
      };
    };

    # Bootstrap configuration
    bootstrap = {
      dcs = {
        ttl = 30;
        loop_wait = 10;
        retry_timeout = 10;
        maximum_lag_on_failover = 1048576;

        postgresql = {
          use_pg_rewind = true;
          use_slots = true;
        };
      };

      initdb = [
        { encoding = "UTF8"; }
        { data-checksums = true; }
      ];

      # Create replication user
      users = {
        replicator = {
          password = "CHANGE_ME_REPLICATOR_PASSWORD";
          options = [ "replication" ];
        };
        uptrack = {
          password = "CHANGE_ME_UPTRACK_PASSWORD";
          options = [ "createrole" "createdb" ];
        };
      };

      # pg_hba.conf
      pg_hba = [
        "host replication replicator 127.0.0.1/32 md5"
        "host replication replicator ${nodeATailscaleIP}/32 md5"
        "host replication replicator ${nodeBTailscaleIP}/32 md5"
        "host replication replicator ${nodeCTailscaleIP}/32 md5"
        "host all all 127.0.0.1/32 md5"
        "host all all ${nodeATailscaleIP}/32 md5"
        "host all all ${nodeBTailscaleIP}/32 md5"
        "host all all ${nodeCTailscaleIP}/32 md5"
      ];
    };
  };

  # Ensure Patroni starts after etcd and PostgreSQL
  systemd.services.patroni = {
    after = [ "etcd.service" "postgresql.service" "tailscaled.service" ];
    requires = [ "etcd.service" "tailscaled.service" ];

    # Stop PostgreSQL if it's running (Patroni will manage it)
    preStart = ''
      ${pkgs.systemd}/bin/systemctl stop postgresql || true
    '';
  };
}
