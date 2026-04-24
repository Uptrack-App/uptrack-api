# VictoriaLogs Single-Node Module
# Stores DOWN-check forensic events written by the Elixir app nodes.
# Dual-write is done app-side (one Gun connection per app-shard per VL
# destination), so no vlagent sidecar is needed.
#
# Deployed on nbg3 + nbg4 as independent instances.
#
# Ports:
#   9428 - HTTP API (insert via /insert/jsonline, query via /select/logsql/query)
#
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.victorialogs;
in {
  options.services.uptrack.victorialogs = {
    enable = mkEnableOption "VictoriaLogs single-node log database";

    package = mkOption {
      type = types.package;
      default = pkgs.victorialogs;
      description = "VictoriaLogs package to use";
    };

    retentionPeriod = mkOption {
      type = types.str;
      default = "2y";
      description = "Data retention period (e.g., 2y for two years, 90d for ninety days)";
    };

    httpListenAddr = mkOption {
      type = types.str;
      default = ":9428";
      description = "HTTP API listen address. Default :9428 binds all interfaces; firewall limits access to Tailscale mesh.";
    };

    httpIdleConnTimeout = mkOption {
      type = types.str;
      default = "10m";
      description = "Close idle HTTP connections after this duration. Default 1m would churn app-side Gun connections; 10m keeps them stable through quiet periods.";
    };

    memoryMax = mkOption {
      type = types.str;
      default = "3G";
      description = "Systemd cgroup MemoryMax for the VL service.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra CLI args passed to victoria-logs.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.victorialogs = {
      description = "VictoriaLogs Log Database";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = concatStringsSep " " ([
          "${cfg.package}/bin/victoria-logs"
          "-storageDataPath=/var/lib/victorialogs"
          "-retentionPeriod=${cfg.retentionPeriod}"
          "-httpListenAddr=${cfg.httpListenAddr}"
          "-http.idleConnTimeout=${cfg.httpIdleConnTimeout}"
        ] ++ cfg.extraArgs);
        Restart = "on-failure";
        RestartSec = "5s";

        TimeoutStartSec = "30s";
        TimeoutStopSec = "30s";

        StateDirectory = "victorialogs";
        User = "victorialogs";
        Group = "victorialogs";

        MemoryMax = cfg.memoryMax;

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/victorialogs" ];
      };
    };

    users.users.victorialogs = {
      isSystemUser = true;
      group = "victorialogs";
      home = "/var/lib/victorialogs";
    };

    users.groups.victorialogs = { };
  };
}
