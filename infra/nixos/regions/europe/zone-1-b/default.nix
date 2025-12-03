# Zone 1-B - Replica Node (hostkey28628)
# IP: 194.180.207.225
# Tailscale: 100.64.1.2
# Services: etcd (2/3), PostgreSQL Replica, vmstorage-zone1-b, vmselect-zone1
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
  networking.hostName = "uptrack-zone-1-b";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "zone-1-b";
    NODE_ZONE = "zone-1";
    NODE_REGION = "europe";
    NODE_PROVIDER = "hostkey";
    NODE_LOCATION = "italy";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.2 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "zone-1-b";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" "tag:zone-1" ];
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
