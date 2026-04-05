# Netcup Nuremberg Node 1 (nbg1) - Coordinator Primary + API
# IP: 152.53.181.117
# Tailscale: 100.64.1.1
# Services: Phoenix API, cloudflared, PostgreSQL Coordinator Primary,
#           Patroni (coordinator), etcd (1/3), vmagent, vmalert
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
    ../../../modules/services/cloudflared.nix
    ../../../modules/services/node-exporter.nix
    ../../../modules/services/vmagent.nix
    ../../../modules/services/vmalert.nix
  ];

  # Hostname
  networking.hostName = "nbg1";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg1";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.1 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg1";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
    # servePort requires Tailscale Serve to be enabled on the tailnet
    # Enable via: https://login.tailscale.com/admin/settings/features
    # servePort = 4000;
  };

  # Phoenix API application
  services.uptrack = {
    enable = true;
    port = 4000;
    host = "api.uptrack.app";
    poolSize = 10;
    obanPoolSize = 20;
    runMigrations = true;
    nodeRegion = "europe";
    nodeProvider = "netcup";
    environmentFile = config.age.secrets.uptrack-env.path;
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

  services.uptrack.vmalert = {
    enable = true;
    datasourceUrl = "http://100.117.191.50:8428";
    remoteWriteUrl = "http://100.117.191.50:8428/api/v1/write";
  };

  # Cloudflare Tunnel for public API access
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
