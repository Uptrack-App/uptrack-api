# Netcup Nuremberg Node 3 (nbg3) - Citus Worker 2
# IP: 152.53.180.51
# Tailscale: 100.64.1.3
# Services: PostgreSQL Citus Worker, vminsert, vmselect, vmagent
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
  networking.hostName = "nbg3";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg3";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.64.1.3 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg3";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" "tag:worker" ];
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
