# Patroni - PostgreSQL High Availability with automatic failover
# Two Patroni clusters sharing one etcd (nbg1-3):
#   - "coordinator" cluster: nbg1 (primary) + nbg2 (standby) — Phoenix API, Oban jobs
#   - "worker" cluster: nbg3 (primary) + nbg4 (standby) — Citus shards
#
# Both clusters use etcd at 100.64.1.{1,2,3}:2379 for DCS (leader election).
# Passwords are loaded from agenix secrets via environment variables.
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Tailscale IPs (static, assigned via Tailscale admin console)
  nodes = {
    nbg1 = "100.64.1.1";
    nbg2 = "100.64.1.2";
    nbg3 = "100.64.1.3";
    nbg4 = "100.64.1.4";
  };

  # Cluster membership
  coordinatorNodes = [ "nbg1" "nbg2" ];
  workerNodes = [ "nbg3" "nbg4" ];
  allPatroniNodes = coordinatorNodes ++ workerNodes;

  isPatroniNode = builtins.elem nodeName allPatroniNodes;
  isCoordinator = builtins.elem nodeName coordinatorNodes;

  nodeIP = if builtins.hasAttr nodeName nodes then nodes.${nodeName} else null;

  # Cluster scope determines Patroni namespace in etcd
  clusterScope = if isCoordinator then "coordinator" else "worker";

  # Peer nodes within same cluster
  clusterPeerNodes = if isCoordinator then coordinatorNodes else workerNodes;
  otherNodes = builtins.filter (n: n != nodeName) clusterPeerNodes;
  otherIPs = map (n: nodes.${n}) otherNodes;

  # All Tailscale IPs for pg_hba
  allNodeIPs = builtins.attrValues nodes;

  # PostgreSQL 17 with Citus and pgvector (pgvector required by twofolk FAQ search)
  pgPackage = pkgs.postgresql_17.withPackages (ps: [ ps.citus ps.pgvector ]);

in lib.mkIf isPatroniNode {
  # Declare agenix secrets for this node
  age.secrets = {
    postgres-password = {
      file = ../../secrets/postgres-password.age;
      owner = "patroni";
      group = "patroni";
      mode = "0400";
    };
    replicator-password = {
      file = ../../secrets/replicator-password.age;
      owner = "patroni";
      group = "patroni";
      mode = "0400";
    };
    uptrack-app-password = {
      file = ../../secrets/uptrack-app-password.age;
      owner = "patroni";
      group = "patroni";
      mode = "0400";
    };
  };

  # Patroni HA manager
  services.patroni = {
    enable = true;
    name = nodeName;
    scope = clusterScope;
    namespace = "/service";

    nodeIp = nodeIP;
    otherNodesIps = otherIPs;
    restApiPort = 8008;

    postgresqlPackage = pgPackage;
    postgresqlPort = 5432;

    # Passwords loaded from agenix secrets via environment variables
    # Patroni reads PATRONI_SUPERUSER_PASSWORD and PATRONI_REPLICATION_PASSWORD
    environmentFiles = {
      PATRONI_SUPERUSER_PASSWORD = config.age.secrets.postgres-password.path;
      PATRONI_REPLICATION_PASSWORD = config.age.secrets.replicator-password.path;
    };

    # All Patroni config goes into settings as freeform YAML
    settings = {
      etcd3 = {
        hosts = builtins.concatStringsSep "," [
          "${nodes.nbg1}:2379"
          "${nodes.nbg2}:2379"
          "${nodes.nbg3}:2379"
        ];
      };

      bootstrap = {
        dcs = {
          ttl = 30;
          loop_wait = 10;
          retry_timeout = 10;
          maximum_lag_on_failover = 1048576;
          synchronous_mode = true;

          postgresql = {
            use_pg_rewind = true;
            use_slots = true;
            parameters = {
              shared_preload_libraries = "citus";
              wal_level = "replica";
              max_wal_senders = 10;
              max_replication_slots = 10;
              hot_standby = "on";

              # Memory (8GB nodes, shared with other services)
              shared_buffers = "1GB";
              effective_cache_size = "3GB";
              maintenance_work_mem = "256MB";
              work_mem = "8MB";

              max_connections = 200;
              checkpoint_completion_target = 0.9;
              min_wal_size = "256MB";
              max_wal_size = "1GB";
            };
          };
        };

        initdb = [
          { encoding = "UTF8"; }
          "data-checksums"
          { locale = "en_US.UTF-8"; }
        ];

        # Users created on bootstrap — passwords come from environment variables
        users = {
          replicator = {
            options = [ "replication" ];
          };
          uptrack_app_user = {
            options = [ "createrole" "createdb" ];
          };
        };

        # Trust Tailscale IPs for inter-node Citus communication
        # Tailscale provides authentication at the network level
        pg_hba = lib.flatten [
          "local all all trust"
          "local replication all trust"
          (map (ip: "host replication replicator ${ip}/32 md5") allNodeIPs)
          "host replication replicator 127.0.0.1/32 md5"
          (map (ip: "host all all ${ip}/32 trust") allNodeIPs)
          "host all all 127.0.0.1/32 trust"
          # Allow admin access from any Tailscale IP (CGNAT range)
          "host all uptrack_app_user 100.64.0.0/10 md5"
          "hostssl all uptrack_app_user 100.64.0.0/10 md5"
        ];

        # Post-bootstrap script: setup Citus after fresh cluster creation
        post_bootstrap = "bash /etc/patroni-post-bootstrap.sh";
      };

      postgresql = {
        authentication = {
          replication = {
            username = "replicator";
            # Password loaded from PATRONI_REPLICATION_PASSWORD env var
          };
          superuser = {
            username = "postgres";
            # Password loaded from PATRONI_SUPERUSER_PASSWORD env var
          };
        };
        parameters = {
          # Use /run/patroni for socket (patroni user has access)
          unix_socket_directories = "/run/patroni";
          shared_preload_libraries = "citus";
        };
      };
    };
  };

  # Create socket directory for PostgreSQL (owned by patroni)
  systemd.tmpfiles.rules = [
    "d /run/patroni 0755 patroni patroni -"
  ];

  # Post-bootstrap script for Citus setup (runs only on fresh cluster creation)
  environment.etc."patroni-post-bootstrap.sh" = {
    mode = "0755";
    text = ''
      #!/bin/bash
      set -e

      # Wait for PostgreSQL to be ready
      until pg_isready -h /run/patroni -U postgres; do
        sleep 1
      done

      # Install Citus extension
      psql -h /run/patroni -U postgres -c "CREATE EXTENSION IF NOT EXISTS citus;"

      # Create application database and grant permissions
      psql -h /run/patroni -U postgres -c "CREATE DATABASE uptrack OWNER uptrack_app_user;"
      psql -h /run/patroni -U postgres -d uptrack -c "GRANT ALL PRIVILEGES ON DATABASE uptrack TO uptrack_app_user;"
      psql -h /run/patroni -U postgres -d uptrack -c "GRANT ALL ON SCHEMA public TO uptrack_app_user;"

      # Set password for application user
      APP_PASSWORD=$(cat ${config.age.secrets.uptrack-app-password.path})
      psql -h /run/patroni -U postgres -c "ALTER USER uptrack_app_user WITH PASSWORD '$APP_PASSWORD'"

      ${if isCoordinator then ''
      # Coordinator-specific setup: register self and add worker node
      # Wait a bit for worker cluster to be ready
      sleep 10

      # Set this node as the coordinator
      psql -h /run/patroni -U postgres -c "SELECT citus_set_coordinator_host('${nodes.nbg2}', 5432);"

      # Add worker node (retry until worker is available)
      for i in {1..30}; do
        if psql -h /run/patroni -U postgres -c "SELECT citus_add_node('${nodes.nbg3}', 5432);" 2>/dev/null; then
          echo "Worker node added successfully"
          break
        fi
        echo "Waiting for worker node... attempt $i"
        sleep 5
      done

      # Install Citus in uptrack database
      psql -h /run/patroni -U postgres -d uptrack -c "CREATE EXTENSION IF NOT EXISTS citus;"
      '' else ''
      # Worker cluster setup complete
      echo "Worker node setup complete"
      ''}
    '';
  };

  # Systemd overrides: Patroni depends on etcd + Tailscale
  systemd.services.patroni = {
    after = [ "etcd.service" "tailscaled.service" "tailscale-autoconnect.service" ];
    requires = [ "tailscaled.service" ];

    serviceConfig = {
      TimeoutSec = lib.mkForce 120;
      RestartSec = 10;
    };
  };

  # Firewall: allow PostgreSQL + Patroni API on Tailscale interface
  networking.firewall.allowedTCPPorts = [ 5432 8008 ];
}
