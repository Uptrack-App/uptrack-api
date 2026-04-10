# Netcup Nuremberg Node 2 (nbg2) - Coordinator Standby + API
# IP: 152.53.183.208
# Tailscale: 100.64.1.2
# Services: Phoenix API, cloudflared, PostgreSQL Coordinator Standby,
#           Patroni (coordinator), etcd (2/3), vmagent
# HAProxy routes DB writes to current Patroni primary (nbg1 or nbg2),
# so both nodes are fully write-capable regardless of PostgreSQL primary location.
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/netcup.nix
    ../../../modules/services/tailscale.nix
    ../../../modules/services/etcd.nix
    ../../../modules/services/patroni.nix
    ../../../modules/services/pgbouncer.nix
    ../../../modules/services/haproxy.nix
    ../../../modules/services/postgres-exporter.nix
    ../../../modules/services/uptrack-app.nix
    ../../../modules/services/stalwart.nix
    ../../../modules/services/cloudflared.nix
    ../../../modules/services/node-exporter.nix
    ../../../modules/services/victoria-metrics.nix
    ../../../modules/services/vmagent.nix
  ];

  # VictoriaMetrics — time-series store for check results (HA: runs on both nbg1+nbg2)
  services.uptrack.victoria-metrics.enable = true;

  # Stalwart outbound SMTP relay — listens on localhost + Tailscale IP.
  # nbg1 uses 100.64.1.2:587 as its smtpFallbackHost.
  services.uptrack.stalwart = {
    enable = true;
    bindAddresses = [ "127.0.0.1" "100.64.1.2" ];
  };

  # Hostname
  networking.hostName = "nbg2";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg2";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.2 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg2";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
    # servePort requires Tailscale Serve to be enabled on the tailnet
    # servePort = 4000;
  };

  # Phoenix API application
  services.uptrack = {
    enable = true;
    port = 4000;
    host = "api.uptrack.app";
    poolSize = 10;
    obanPoolSize = 20;
    runMigrations = false; # Only nbg1 runs migrations to avoid race conditions
    nodeRegion = "europe";
    nodeProvider = "netcup";
    environmentFile = config.age.secrets.uptrack-env.path;
    smtpFallbackHost = "100.64.1.1"; # nbg1 Tailscale IP
  };

  # VictoriaMetrics monitoring
  # vmagent writes to both nbg3+nbg4 for replication
  services.uptrack.vmagent = {
    enable = true;
    remoteWriteUrls = [
      "http://100.117.191.50:8428/api/v1/write"
      "http://100.72.224.65:8428/api/v1/write"
    ];
  };

  # Cloudflare Tunnel — same token as nbg1, Cloudflare treats both as redundant connectors.
  # If nbg1 dies, Cloudflare routes all traffic here automatically within ~5s.
  services.uptrack.cloudflared = {
    enable = true;
    tunnelTokenFile = config.age.secrets.cloudflared-tunnel-token.path;
  };

  # Agenix secrets
  age.secrets.cloudflared-tunnel-token = {
    file = ../../../secrets/cloudflared-tunnel-token.age;
    owner = "cloudflared";
    group = "cloudflared";
    mode = "0400";
  };

  age.secrets.uptrack-env = {
    file = ../../../secrets/uptrack-env.age;
    owner = "uptrack";
    group = "uptrack";
    mode = "0400";
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
