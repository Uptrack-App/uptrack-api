# OVH Canada - App-Only Node
# Tailscale IP: 100.64.0.3
# 4 vCPU, 8 GB RAM, 75 GB Storage
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../../common/base.nix
    ../../../common/ovh.nix
    ../../../modules/profiles/app-only.nix
  ];

  # Hostname
  networking.hostName = "uptrack-canada";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "canada";
    NODE_REGION = "americas";
    NODE_PROVIDER = "ovh";
    NODE_LOCATION = "canada";

    # No database roles (app-only)

    # Tailscale
    TAILSCALE_IP = "100.64.0.3";
  };

  # Open ports for services
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # HTTP
    443   # HTTPS
    4000  # Phoenix app
    2379  # etcd client
    2380  # etcd peer
  ];

  # Journald configuration
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=2G
  '';
}
