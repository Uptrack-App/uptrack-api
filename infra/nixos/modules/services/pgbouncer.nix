# PgBouncer - Connection Pooling for PostgreSQL
# Deployed on coordinator nodes (nbg1, nbg2) to pool Phoenix connections.
# Uses transaction pooling mode for Ecto compatibility.
#
# Architecture:
#   Phoenix (port 4000) → PgBouncer (port 6432) → Patroni/PostgreSQL (port 5432)
#
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Tailscale IPs (must match patroni.nix)
  nodes = {
    nbg1 = "100.64.1.1";
    nbg2 = "100.112.11.29";
    nbg3 = "100.117.191.50";
    nbg4 = "100.72.224.65";
  };

  # PgBouncer runs on coordinator nodes only
  coordinatorNodes = [ "nbg1" "nbg2" ];
  isPgBouncerNode = builtins.elem nodeName coordinatorNodes;

  nodeIP = if builtins.hasAttr nodeName nodes then nodes.${nodeName} else null;

in lib.mkIf isPgBouncerNode {
  # Declare agenix secret for app user password
  age.secrets.pgbouncer-userlist = {
    file = ../../secrets/uptrack-app-password.age;
    owner = "pgbouncer";
    group = "pgbouncer";
    mode = "0400";
  };

  # PgBouncer service using NixOS module
  services.pgbouncer = {
    enable = true;
    openFirewall = true;  # Opens port 6432

    settings = {
      # Database section - connect to Patroni via Tailscale IP
      databases = {
        uptrack = "host=${nodeIP} port=5432 dbname=uptrack";
      };

      # PgBouncer settings
      pgbouncer = {
        # Listen configuration
        listen_addr = "${nodeIP},127.0.0.1";
        listen_port = 6432;

        # Transaction pooling - required for Ecto prepared statements
        pool_mode = "transaction";

        # Connection limits
        max_client_conn = 400;      # Phoenix + Oban combined
        default_pool_size = 50;     # Connections per user/database
        min_pool_size = 5;          # Keep minimum connections warm
        reserve_pool_size = 5;      # Extra connections for burst

        # Timeouts
        server_connect_timeout = 15;
        server_idle_timeout = 600;
        client_idle_timeout = 0;    # No client timeout
        query_timeout = 0;          # No query timeout (Ecto handles)

        # Authentication
        auth_type = "md5";
        auth_file = "/run/pgbouncer/userlist.txt";

        # Admin access
        admin_users = "pgbouncer";
        stats_users = "pgbouncer";

        # Logging
        log_connections = 1;
        log_disconnections = 1;
        log_pooler_errors = 1;

        # Set search_path on every new server connection so Ecto resolves
        # custom types in the app schema (e.g. team_role) through PgBouncer
        server_reset_query = "DISCARD ALL; SET search_path TO app, public";

        # Ignore Ecto startup params
        ignore_startup_parameters = "extra_float_digits";
      };
    };
  };

  # Create userlist.txt with password from agenix
  systemd.services.pgbouncer-userlist = {
    description = "Generate PgBouncer userlist from agenix secrets";
    wantedBy = [ "pgbouncer.service" ];
    before = [ "pgbouncer.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      mkdir -p /run/pgbouncer
      chown pgbouncer:pgbouncer /run/pgbouncer

      # Read password from agenix secret
      APP_PASSWORD=$(cat ${config.age.secrets.pgbouncer-userlist.path})

      # Generate userlist.txt with md5 hashed password
      # Format: "username" "md5<hash>" where hash is md5(password + username)
      MD5_HASH=$(echo -n "$APP_PASSWORD"uptrack_app_user | md5sum | cut -d' ' -f1)

      cat > /run/pgbouncer/userlist.txt << EOF
"uptrack_app_user" "md5$MD5_HASH"
"pgbouncer" ""
EOF

      chown pgbouncer:pgbouncer /run/pgbouncer/userlist.txt
      chmod 0600 /run/pgbouncer/userlist.txt
    '';
  };

  # Systemd overrides: PgBouncer depends on Patroni
  systemd.services.pgbouncer = {
    after = [ "patroni.service" "pgbouncer-userlist.service" ];
    wants = [ "patroni.service" ];

    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };
  };
}
