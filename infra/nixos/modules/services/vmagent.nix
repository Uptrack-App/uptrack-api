# VictoriaMetrics Agent Module
# Scrapes Prometheus-compatible metrics from all infrastructure services
# and forwards them to VictoriaMetrics single-node instances.
# Deployed to nbg1 + nbg2. Writes to both nbg3+nbg4 for replication.
#
# Port: 8429 (HTTP API for status/targets)
#
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.vmagent;

  # Default scrape config targeting all infrastructure services
  defaultScrapeConfig = pkgs.writeText "vmagent-scrape.yml" ''
    global:
      scrape_interval: 30s
      scrape_timeout: 10s

    scrape_configs:
      # Node exporters on all nodes
      - job_name: node_exporter
        static_configs:
          - targets:
              - "100.64.1.1:9100"
              - "100.64.1.2:9100"
              - "100.117.191.50:9100"
              - "100.72.224.65:9100"
            labels:
              cluster: uptrack

      # PostgreSQL exporters (via postgres-exporter on Patroni nodes)
      - job_name: postgres_exporter
        static_configs:
          - targets:
              - "100.64.1.1:9187"
              - "100.64.1.2:9187"
              - "100.117.191.50:9187"
              - "100.72.224.65:9187"

      # etcd cluster (nbg1, nbg2, nbg3)
      - job_name: etcd
        static_configs:
          - targets:
              - "100.64.1.1:2379"
              - "100.64.1.2:2379"
              - "100.117.191.50:2379"

      # Patroni REST API (coordinator + worker clusters)
      - job_name: patroni
        static_configs:
          - targets:
              - "100.64.1.1:8008"
              - "100.64.1.2:8008"
              - "100.117.191.50:8008"
              - "100.72.224.65:8008"

      # VictoriaMetrics single-node instances (nbg3 + nbg4)
      - job_name: victoria_metrics
        static_configs:
          - targets:
              - "100.117.191.50:8428"
              - "100.72.224.65:8428"

      # vmagent self-monitoring (nbg1 + nbg2)
      - job_name: vmagent
        static_configs:
          - targets:
              - "100.64.1.1:8429"
              - "100.64.1.2:8429"
  '';

  # Build the list of -remoteWrite.url flags
  remoteWriteFlags = map (url: "-remoteWrite.url=${url}") cfg.remoteWriteUrls;
in {
  options.services.uptrack.vmagent = {
    enable = mkEnableOption "VictoriaMetrics scrape agent";

    package = mkOption {
      type = types.package;
      default = pkgs.victoriametrics;
      description = "VictoriaMetrics package to use";
    };

    remoteWriteUrls = mkOption {
      type = types.listOf types.str;
      description = "URLs of VictoriaMetrics instances to write metrics to (one -remoteWrite.url per entry)";
      example = [ "http://100.117.191.50:8428/api/v1/write" "http://100.72.224.65:8428/api/v1/write" ];
    };

    scrapeConfigFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Custom Prometheus scrape config file. If null, uses built-in default.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8429;
      description = "HTTP API port for agent status and targets";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.vmagent = {
      description = "VictoriaMetrics Agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = concatStringsSep " " ([
          "${cfg.package}/bin/vmagent"
        ] ++ remoteWriteFlags ++ [
          "-promscrape.config=${if cfg.scrapeConfigFile != null then cfg.scrapeConfigFile else defaultScrapeConfig}"
          "-remoteWrite.tmpDataPath=/var/lib/vmagent/remotewrite-data"
          "-httpListenAddr=:${toString cfg.httpPort}"
        ]);
        Restart = "on-failure";
        RestartSec = "5s";

        # Timeouts
        TimeoutStartSec = "30s";
        TimeoutStopSec = "10s";

        # State (for WAL/buffer during remote write failures)
        StateDirectory = "vmagent";
        User = "vmagent";
        Group = "vmagent";

        # Security
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/vmagent" ];

        # Resources
        MemoryMax = "512M";
      };
    };

    users.users.vmagent = {
      isSystemUser = true;
      group = "vmagent";
      home = "/var/lib/vmagent";
    };

    users.groups.vmagent = {};
  };
}
