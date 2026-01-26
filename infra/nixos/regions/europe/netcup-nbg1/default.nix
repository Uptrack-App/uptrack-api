# Netcup Nuremberg Node 1 (nbg1) - Coordinator Primary + Phoenix API
# IP: 152.53.181.117
# Tailscale: 100.64.1.1
# Services: Phoenix API, PostgreSQL Coordinator Primary, etcd, vmstorage
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
