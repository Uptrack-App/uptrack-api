{ config, lib, pkgs, ... }:

let
  cfg = config.services.twofolk;
in
{
  options.services.twofolk = {
    enable = lib.mkEnableOption "2folk AI chat service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4001;
      description = "Port for the Phoenix HTTP server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "app.2folk.com";
      description = "Public hostname";
    };

    poolSize = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Database connection pool size";
    };

    runMigrations = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run database migrations on startup";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to environment file with secrets";
    };

    releaseDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/twofolk";
      description = "Path to the twofolk release directory (deployed by deploy.sh)";
    };
  };

  config = lib.mkIf cfg.enable {
    # System user
    users.users.twofolk = {
      isSystemUser = true;
      group = "twofolk";
      home = "/var/lib/twofolk";
      createHome = true;
    };
    users.groups.twofolk = { };

    # Persistent directories
    systemd.tmpfiles.rules = [
      "d /var/data/2folk/uploads 0755 twofolk twofolk -"
    ];

    # Migration service — runs before app starts
    systemd.services.twofolk-migrate = lib.mkIf cfg.runMigrations {
      description = "2folk database migrations";
      wantedBy = [ "multi-user.target" ];
      before = [ "twofolk.service" ];
      requiredBy = [ "twofolk.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "twofolk";
        Group = "twofolk";
        WorkingDirectory = "/var/lib/twofolk";
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.releaseDir}/bin/twofolk eval 'Twofolk.Release.migrate()'";
        TimeoutStartSec = 120;
      };

      environment = {
        PHX_SERVER = "false";
        POOL_SIZE = "2";
        UPLOAD_DIR = "/var/data/2folk/uploads";
      };
    };

    # Main application service
    systemd.services.twofolk = {
      description = "2folk AI chat for Shopify";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "twofolk-migrate.service" ];

      serviceConfig = {
        Type = "exec";
        User = "twofolk";
        Group = "twofolk";
        WorkingDirectory = "/var/lib/twofolk";
        EnvironmentFile = cfg.environmentFile;
        ExecStart = "${cfg.releaseDir}/bin/twofolk start";
        ExecStop = "${cfg.releaseDir}/bin/twofolk stop";
        Restart = "on-failure";
        RestartSec = 5;

        # Resource limits
        LimitNOFILE = 65536;
        MemoryMax = "2G";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/twofolk" "/var/data/2folk" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };

      environment = {
        PHX_SERVER = "true";
        PHX_HOST = cfg.host;
        PORT = toString cfg.port;
        POOL_SIZE = toString cfg.poolSize;
        UPLOAD_DIR = "/var/data/2folk/uploads";
      };
    };
  };
}
