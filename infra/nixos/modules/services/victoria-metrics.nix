# VictoriaMetrics Single-Node Module
# Runs victoria-metrics in single-node mode (storage + insert + select).
# For our scale (~666 samples/sec), this is the recommended architecture.
#
# HA Strategy: Run on nbg3 + nbg4 as independent instances.
# vmagent writes to both, so each has a full copy of all data.
# Queries can go to either instance.
#
# Ports:
#   8428 - HTTP API (insert via /api/v1/write, query via /api/v1/query)
#
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.victoria-metrics;
in {
  options.services.uptrack.victoria-metrics = {
    enable = mkEnableOption "VictoriaMetrics single-node time-series database";

    package = mkOption {
      type = types.package;
      default = pkgs.victoriametrics;
      description = "VictoriaMetrics package to use";
    };

    retentionPeriod = mkOption {
      type = types.str;
      default = "15";
      description = "Data retention period in months (plain number, e.g., 15 = 15 months)";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8428;
      description = "HTTP API port for writes, queries, and health checks";
    };

    dedupInterval = mkOption {
      type = types.str;
      default = "30s";
      description = "Deduplication interval for data received from multiple vmagent instances";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.victoria-metrics = {
      description = "VictoriaMetrics Time-Series Database";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = concatStringsSep " " [
          "${cfg.package}/bin/victoria-metrics"
          "-storageDataPath=/var/lib/victoria-metrics"
          "-retentionPeriod=${cfg.retentionPeriod}"
          "-dedup.minScrapeInterval=${cfg.dedupInterval}"
          "-httpListenAddr=:${toString cfg.httpPort}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";

        # Timeouts
        TimeoutStartSec = "30s";
        TimeoutStopSec = "30s";

        # State
        StateDirectory = "victoria-metrics";
        User = "victoria-metrics";
        Group = "victoria-metrics";

        # Resources
        MemoryMax = "3G";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/victoria-metrics" ];
      };
    };

    users.users.victoria-metrics = {
      isSystemUser = true;
      group = "victoria-metrics";
      home = "/var/lib/victoria-metrics";
    };

    users.groups.victoria-metrics = {};
  };
}
