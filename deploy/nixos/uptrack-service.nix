# NixOS service configuration for Uptrack with Idle Prevention
# Place this in /etc/nixos/uptrack-service.nix or similar location

{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack;
  uptrackPackage = pkgs.callPackage ./uptrack.nix { };
in
{
  options = {
    services.uptrack = {
      enable = mkEnableOption "Uptrack monitoring service";

      package = mkOption {
        type = types.package;
        default = uptrackPackage;
        description = "Uptrack package to use";
      };

      environment = mkOption {
        type = types.str;
        default = "prod";
        description = "Environment (prod, dev, test)";
      };

      port = mkOption {
        type = types.port;
        default = 4000;
        description = "Port to listen on";
      };

      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host to bind to";
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

      databaseUrl = mkOption {
        type = types.str;
        description = "Database connection URL";
        example = "postgresql://user:password@localhost/uptrack";
      };

      secretKeyBase = mkOption {
        type = types.str;
        description = "Phoenix secret key base";
      };

      idlePreventionEnabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable idle prevention for Oracle Always Free instances";
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

      logDir = mkOption {
        type = types.path;
        default = "/var/log/uptrack";
        description = "Log directory";
      };
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.workDir;
      createHome = true;
      shell = pkgs.nologin;
    };

    users.groups.${cfg.group} = { };

    # Create directories
    systemd.tmpfiles.rules = [
      "d ${cfg.workDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.logDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Main service
    systemd.services.uptrack = {
      description = "Uptrack Monitoring Service";
      after = [ "network.target" "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        MIX_ENV = cfg.environment;
        PHX_HOST = cfg.host;
        PHX_PORT = toString cfg.port;
        APP_POOL_SIZE = toString cfg.poolSize;
        OBAN_POOL_SIZE = toString cfg.obanPoolSize;
        DATABASE_URL = cfg.databaseUrl;
        SECRET_KEY_BASE = cfg.secretKeyBase;
        IDLE_PREVENTION_ENABLED = lib.boolToString cfg.idlePreventionEnabled;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.workDir;

        # Start service
        ExecStart = "${cfg.package}/bin/uptrack start";

        # Restart policy
        Restart = "on-failure";
        RestartSec = "5s";

        # Resource limits
        MemoryMax = "2G";
        CPUQuota = "400%";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.workDir cfg.logDir ];
        StandardOutput = "journal";
        StandardError = "journal";
      };

      postStart = ''
        # Wait for application to be ready
        for i in {1..30}; do
          if ${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}/api/health > /dev/null 2>&1; then
            echo "Uptrack is ready"
            exit 0
          fi
          sleep 1
        done
        echo "Warning: Uptrack did not become ready within 30 seconds"
      '';

      preStop = ''
        # Graceful shutdown
        ${pkgs.systemd}/bin/systemctl kill -s SIGTERM uptrack
      '';
    };

    # Optional: Health check timer
    systemd.timers.uptrack-healthcheck = mkIf cfg.idlePreventionEnabled {
      description = "Uptrack Health Check Timer";
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
        Unit = "uptrack-healthcheck.service";
      };
      wantedBy = [ "timers.target" ];
    };

    systemd.services.uptrack-healthcheck = mkIf cfg.idlePreventionEnabled {
      description = "Uptrack Health Check Service";
      script = ''
        ${pkgs.curl}/bin/curl -f http://localhost:${toString cfg.port}/api/health > /dev/null 2>&1
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    # Optional: Monitoring integration (Prometheus)
    services.prometheus.scrapeConfigs = mkIf cfg.idlePreventionEnabled [
      {
        job_name = "uptrack";
        static_configs = [
          {
            targets = [ "localhost:${toString cfg.port}" ];
          }
        ];
        metrics_path = "/metrics";
      }
    ];
  };
}
