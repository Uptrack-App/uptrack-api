# Netcup Nuremberg Node 2 (nbg2) - Coordinator Standby + API
# IP: 152.53.183.208
# Tailscale: 100.64.1.2
# Services: Phoenix API, cloudflared, PostgreSQL Coordinator Standby,
#           Patroni (coordinator), etcd (2/3), vminsert, vmselect, vmagent
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
    ../../../modules/services/postgres-exporter.nix
  ];

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
    # Advertise Phoenix API for Tailscale Services load balancing
    servePort = 4000;
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
