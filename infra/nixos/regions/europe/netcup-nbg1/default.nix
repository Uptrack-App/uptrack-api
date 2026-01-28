# Netcup Nuremberg Node 1 (nbg1) - Coordinator Primary + API
# IP: 152.53.181.117
# Tailscale: 100.64.1.1
# Services: Phoenix API, cloudflared, PostgreSQL Coordinator Primary,
#           Patroni (coordinator), etcd (1/3), vminsert, vmselect, vmagent
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
    # Advertise Phoenix API for Tailscale Services load balancing
    servePort = 4000;
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
