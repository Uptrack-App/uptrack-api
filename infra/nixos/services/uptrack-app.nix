# Uptrack Phoenix Application Service
# Runs on all 3 nodes for regional monitoring
{ config, pkgs, lib, ... }:

let
  # Build the Phoenix release
  uptrackApp = pkgs.callPackage ../packages/uptrack-app.nix { };

  # App user
  uptrackUser = "uptrack-app";
  uptrackGroup = "uptrack-app";

  nodeName = config.networking.hostName;
  nodeRegion = if nodeName == "uptrack-node-a" then "us-east"
                else if nodeName == "uptrack-node-b" then "eu-central"
                else "ap-southeast";
  obanNodeName = if nodeName == "uptrack-node-a" then "node-a"
                 else if nodeName == "uptrack-node-b" then "node-b"
                 else "node-c";

  # Tailscale IPs
  nodeCTailscaleIP = "100.64.0.3";

in {
  # Configure secret ownership
  age.secrets.uptrack-env = {
    owner = uptrackUser;
    group = uptrackGroup;
    mode = "0444";
  };

  # Create uptrack-app user
  users.users.${uptrackUser} = {
    isSystemUser = true;
    group = uptrackGroup;
    home = "/var/lib/uptrack-app";
    createHome = true;
  };

  users.groups.${uptrackGroup} = { };

  # Uptrack application service
  systemd.services.uptrack-app = {
    description = "Uptrack Phoenix Application";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "tailscaled.service" "patroni.service" ];
    requires = [ "tailscaled.service" ];

    environment = {
      MIX_ENV = "prod";
      PORT = "4000";
      PHX_SERVER = "true";
      PHX_HOST = "uptrack.app";

      # Node identification
      NODE_REGION = nodeRegion;
      OBAN_NODE_NAME = obanNodeName;

      # Database URLs (via HAProxy local proxy)
      DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=app,public";
      OBAN_DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=oban,public";
      RESULTS_DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=results,public";

      # ClickHouse (Node C via Tailscale)
      CLICKHOUSE_HOST = nodeCTailscaleIP;
      CLICKHOUSE_PORT = "8123";
      CLICKHOUSE_DATABASE = "default";

      # Erlang distribution
      RELEASE_COOKIE = "UPTRACK_COOKIE_FOR_DISTRIBUTION";

      LANG = "en_US.UTF-8";
      HOME = "/var/lib/uptrack-app";
    };

    serviceConfig = {
      Type = "exec";
      User = uptrackUser;
      Group = uptrackGroup;
      WorkingDirectory = "${uptrackApp}";

      # Load environment from agenix secret (overrides above)
      EnvironmentFile = config.age.secrets.uptrack-env.path;

      # Start the release
      ExecStart = "${uptrackApp}/bin/uptrack start";

      # Restart policy
      Restart = "on-failure";
      RestartSec = "5s";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/uptrack-app" ];

      # Resource limits
      LimitNOFILE = 65536;
    };

    restartIfChanged = true;
  };

  # Database migration service
  systemd.services.uptrack-migrate = {
    description = "Run Uptrack database migrations";
    after = [ "patroni.service" "tailscaled.service" ];
    requires = [ "patroni.service" ];
    before = [ "uptrack-app.service" ];

    environment = {
      MIX_ENV = "prod";
      DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=app,public";
      OBAN_DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=oban,public";
      RESULTS_DATABASE_URL = "postgresql://uptrack:CHANGE_ME@127.0.0.1:6432/uptrack_prod?search_path=results,public";
      RELEASE_COOKIE = "UPTRACK_COOKIE_FOR_DISTRIBUTION";
    };

    serviceConfig = {
      Type = "oneshot";
      User = uptrackUser;
      Group = uptrackGroup;
      WorkingDirectory = "${uptrackApp}";

      EnvironmentFile = config.age.secrets.uptrack-env.path;

      # Run migrations
      ExecStart = "${uptrackApp}/bin/uptrack eval 'Uptrack.Release.migrate()'";

      RemainAfterExit = true;
    };
  };

  # Create spool directory for ClickHouse writes
  systemd.tmpfiles.rules = [
    "d /var/lib/uptrack-app/spool 0750 ${uptrackUser} ${uptrackGroup} -"
    "d /var/lib/uptrack-app/uploads 0750 ${uptrackUser} ${uptrackGroup} -"
  ];
}
