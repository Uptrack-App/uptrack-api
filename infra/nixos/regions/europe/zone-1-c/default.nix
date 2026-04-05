# Zone 1-C - Witness Node (hostkey48628)
# IP: REMOVED_IP
# Tailscale: 100.117.191.50
# Services: etcd (3/3), PostgreSQL Witness, vmstorage-zone1-c, vmselect-zone1-backup
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/hostkey.nix
    ../../../modules/services/tailscale.nix
  ];

  # Hostname
  networking.hostName = "uptrack-zone-1-c";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "zone-1-c";
    NODE_ZONE = "zone-1";
    NODE_REGION = "europe";
    NODE_PROVIDER = "hostkey";
    NODE_LOCATION = "italy";
  };

  # Tailscale VPN configuration
  # Static IP: 100.117.191.50 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "zone-1-c";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" "tag:zone-1" ];
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
