# VictoriaMetrics Alert Module
# Evaluates alerting rules against vmselect and writes results to vminsert.
# Deployed to nbg1 only.
#
# Port: 8880 (HTTP API for alert status)
#
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.vmalert;

  # Default alert rules for infrastructure monitoring
  defaultRulesFile = pkgs.writeText "vmalert-rules.yml" ''
    groups:
      - name: infrastructure
        interval: 30s
        rules:
          - alert: NodeDown
            expr: up{job="node_exporter"} == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Node {{ $labels.instance }} is down"
              description: "Node exporter on {{ $labels.instance }} has been unreachable for 5 minutes."

          - alert: PostgresPrimaryDown
            expr: up{job="postgres_exporter"} == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "PostgreSQL on {{ $labels.instance }} is down"

          - alert: EtcdQuorumLost
            expr: count(up{job="etcd"} == 1) < 2
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "etcd cluster has lost quorum"
              description: "Fewer than 2 etcd nodes are healthy. Cluster cannot elect leaders."

          - alert: DiskSpaceHigh
            expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.1
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Disk space above 90% on {{ $labels.instance }}"

          - alert: VictoriaMetricsDown
            expr: up{job="victoria_metrics"} == 0
            for: 3m
            labels:
              severity: critical
            annotations:
              summary: "VictoriaMetrics instance {{ $labels.instance }} is down"
              description: "Data ingestion and queries may be degraded."

          - alert: HighMemoryUsage
            expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "High memory usage on {{ $labels.instance }}"
  '';
in {
  options.services.uptrack.vmalert = {
    enable = mkEnableOption "VictoriaMetrics alerting";

    package = mkOption {
      type = types.package;
      default = pkgs.victoriametrics;
      description = "VictoriaMetrics package to use";
    };

    datasourceUrl = mkOption {
      type = types.str;
      description = "URL of vmselect for evaluating alert rules";
      example = "http://127.0.0.1:8481";
    };

    remoteWriteUrl = mkOption {
      type = types.str;
      description = "URL of vminsert for writing alert state metrics";
      example = "http://127.0.0.1:8480/api/v1/write";
    };

    rulesFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Custom alert rules file. If null, uses built-in default.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8880;
      description = "HTTP API port for alert status";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.vmalert = {
      description = "VictoriaMetrics Alert Manager";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = concatStringsSep " " [
          "${cfg.package}/bin/vmalert"
          "-datasource.url=${cfg.datasourceUrl}"
          "-remoteWrite.url=${cfg.remoteWriteUrl}"
          "-notifier.blackhole"
          "-rule=${if cfg.rulesFile != null then cfg.rulesFile else defaultRulesFile}"
          "-httpListenAddr=:${toString cfg.httpPort}"
        ];
        Restart = "on-failure";
        RestartSec = "5s";

        # Timeouts
        TimeoutStartSec = "30s";
        TimeoutStopSec = "10s";

        # Security
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;

        # Resources
        MemoryMax = "256M";
      };
    };
  };
}
