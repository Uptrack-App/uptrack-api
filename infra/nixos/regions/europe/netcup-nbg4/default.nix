# Netcup Nuremberg Node 4 (nbg4) - Coordinator Standby + Phoenix API
# IP: 159.195.56.242
# Tailscale: 100.64.1.4
# Services: Phoenix API, PostgreSQL Coordinator Standby, etcd, vmstorage
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/netcup.nix
    ../../../modules/services/tailscale.nix
  ];

  # Override disko device - Netcup VPS uses /dev/vda (virtio), not /dev/sda
  disko.devices.disk.main.device = "/dev/vda";

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
    tags = [ "tag:infrastructure" "tag:api" ];
    # Advertise Phoenix API for Tailscale Services load balancing
    servePort = 4000;
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
