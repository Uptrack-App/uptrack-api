# Uptrack Phoenix Application Service
# NixOS module for running the Uptrack monitoring platform
{ config, pkgs, lib, self, ... }:

with lib;

let
  cfg = config.services.uptrack;
in
{
  options.services.uptrack = {
    enable = mkEnableOption "Uptrack monitoring service";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../packages/uptrack-app.nix { inherit self; };
      description = "Uptrack package to use";
    };

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port to listen on";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host/domain for URL generation";
    };

    poolSize = mkOption {
      type = types.int;
      default = 10;
      description = "Database connection pool size";
    };

    obanPoolSize = mkOption {
      type = types.int;
      default = 20;
      description = "Oban connection pool size";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to an environment file (e.g. from agenix) containing secrets.
        Expected variables: DATABASE_URL, SECRET_KEY_BASE, and any OAuth/SMTP keys.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "uptrack";
      description = "User to run the service as";
    };

    group = mkOption {
      type = types.str;
      default = "uptrack";
      description = "Group to run the service as";
    };

    workDir = mkOption {
      type = types.path;
      default = "/var/lib/uptrack";
      description = "Working directory for the service";
    };

    runMigrations = mkOption {
      type = types.bool;
      default = true;
      description = "Run Ecto migrations before starting the app";
    };

    idlePrevention = mkOption {
      type = types.bool;
      default = false;
      description = "Enable periodic health check to prevent idle shutdown (Oracle Always Free)";
    };

    nodeRegion = mkOption {
      type = types.str;
      default = "unknown";
      description = "Region identifier for health endpoint (e.g. europe, asia)";
    };

    nodeProvider = mkOption {
      type = types.str;
      default = "unknown";
      description = "Infrastructure provider (e.g. netcup, oracle)";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.workDir;
      createHome = true;
    };

    users.groups.${cfg.group} = { };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.workDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Database migration service (runs before app starts)
    systemd.services.uptrack-migrate = mkIf cfg.runMigrations {
      description = "Uptrack Database Migrations";
      after = [ "network.target" "postgresql.service" ];
      requiredBy = [ "uptrack.service" ];
      before = [ "uptrack.service" ];

      environment = {
        MIX_ENV = "prod";
        PHX_HOST = cfg.host;
        PHX_PORT = toString cfg.port;
        APP_POOL_SIZE = "2";
        RELEASE_COOKIE = "uptrack_prod_cookie";
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workDir;
        ExecStart = "${cfg.package}/bin/uptrack eval 'Uptrack.Release.migrate()'";
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;
        TimeoutStartSec = "120s";
        RemainAfterExit = true;
      };
    };

    # Main Phoenix application service
    systemd.services.uptrack = {
      description = "Uptrack Monitoring Service";
      after = [ "network.target" "postgresql.service" ]
        ++ optional cfg.runMigrations "uptrack-migrate.service";
      wantedBy = [ "multi-user.target" ];

      environment = {
        MIX_ENV = "prod";
        PHX_HOST = cfg.host;
        PHX_PORT = toString cfg.port;
        APP_POOL_SIZE = toString cfg.poolSize;
        OBAN_POOL_SIZE = toString cfg.obanPoolSize;
        RELEASE_TMP = "${cfg.workDir}/tmp";
        RELEASE_COOKIE = "uptrack_prod_cookie";
        NODE_NAME = config.networking.hostName;
        NODE_REGION = cfg.nodeRegion;
        NODE_PROVIDER = cfg.nodeProvider;
      };

      serviceConfig = {
        Type = "exec";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workDir;
        ExecStart = "${cfg.package}/bin/uptrack start";
        ExecStop = "${cfg.package}/bin/uptrack stop";
        EnvironmentFile = mkIf (cfg.environmentFile != null) cfg.environmentFile;

        # Restart policy
        Restart = "on-failure";
        RestartSec = "5s";

        # Timeouts
        TimeoutStartSec = "60s";
        TimeoutStopSec = "30s";

        # Resource limits
        MemoryMax = "4G";
        LimitNOFILE = 65536;

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.workDir ];
        StandardOutput = "journal";
        StandardError = "journal";
      };

      # Health check after start
      postStart = ''
        for i in $(seq 1 30); do
          if ${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.port}/api/health > /dev/null 2>&1; then
            echo "Uptrack is ready"
            exit 0
          fi
          sleep 1
        done
        echo "Warning: Uptrack did not become ready within 30 seconds"
      '';
    };

    # Idle prevention timer (for Oracle Always Free instances)
    systemd.timers.uptrack-healthcheck = mkIf cfg.idlePrevention {
      description = "Uptrack Idle Prevention Timer";
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Unit = "uptrack-healthcheck.service";
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services.uptrack-healthcheck = mkIf cfg.idlePrevention {
      description = "Uptrack Idle Prevention Health Check";
      script = ''
        ${pkgs.curl}/bin/curl -sf http://localhost:${toString cfg.port}/api/health > /dev/null 2>&1
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "nobody";
      };
    };
  };
}
