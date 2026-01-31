# Netcup Nuremberg Node 4 (nbg4) - Citus Worker Standby
# IP: 159.195.56.242
# Tailscale: 100.64.1.4
# Services: PostgreSQL Worker Standby, Patroni (worker), vmstorage
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/netcup.nix
    ../../../modules/services/tailscale.nix
    ../../../modules/services/patroni.nix
    ../../../modules/services/postgres-exporter.nix
  ];

  # Hostname
  networking.hostName = "nbg4";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg4";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.4 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg4";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
