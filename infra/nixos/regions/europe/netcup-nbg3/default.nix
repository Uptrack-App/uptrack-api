# Netcup Nuremberg Node 3 (nbg3) - Citus Worker Primary
# IP: 152.53.180.51
# Tailscale: 100.117.191.50
# Services: PostgreSQL Worker Primary (all shards), Patroni (worker),
#           etcd (3/3), victoria-metrics
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
    ../../../modules/services/node-exporter.nix
    ../../../modules/services/postgres-exporter.nix
    ../../../modules/services/victoria-metrics.nix
    ../../../modules/services/twofolk/app.nix
  ];

  # Hostname
  networking.hostName = "nbg3";

  # ── 2folk AI chat app ─────────────────────────────────────────────

  # Decrypt twofolk secrets at boot → /run/agenix/twofolk-env
  age.secrets.twofolk-env = {
    file = ../../../secrets/twofolk-env.age;
    owner = "twofolk";
    group = "twofolk";
    mode = "0400";
  };

  services.twofolk = {
    enable = true;
    environmentFile = config.age.secrets.twofolk-env.path;
    releaseDir = "/opt/twofolk";
    host = "app.2folk.com";
    port = 4001;
  };

  # Cloudflare → HAProxy :443 → Phoenix :4001 (HAProxy config in haproxy-twofolk.cfg)
  networking.firewall.allowedTCPPorts = [ 80 ];

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg3";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.117.191.50 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg3";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];  # Only tag:infrastructure is permitted by ACL
  };

  # VictoriaMetrics single-node instance
  # HA: independent instance, vmagent writes to both nbg3+nbg4
  services.uptrack.victoria-metrics = {
    enable = true;
    retentionPeriod = "15";
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
