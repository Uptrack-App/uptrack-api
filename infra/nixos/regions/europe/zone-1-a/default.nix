# Zone 1-A - Primary Node (hostkey22275)
# IP: 194.180.207.223
# Tailscale: 100.64.1.1
# Services: etcd (1/3), PostgreSQL Primary, vmstorage-zone1-a, vminsert-zone1
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/hostkey.nix
    ../../../disko/hostkey-bios.nix
    ../../../modules/services/tailscale.nix
  ];

  # Hostname
  networking.hostName = "uptrack-zone-1-a";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "zone-1-a";
    NODE_ZONE = "zone-1";
    NODE_REGION = "europe";
    NODE_PROVIDER = "hostkey";
    NODE_LOCATION = "italy";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.1 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "zone-1-a";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" "tag:zone-1" ];
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
