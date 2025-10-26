# Hetzner Primary Node - Europe
# node-a: 91.98.89.119
# Full stack with HAProxy
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../../common/base.nix
    ../../../common/hetzner.nix
    ../../../modules/profiles/primary.nix
  ];

  # Hostname
  networking.hostName = "uptrack-hetzner-primary";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "hetzner-primary";
    NODE_REGION = "europe";
    NODE_PROVIDER = "hetzner";
  };

  # Open ports for services
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # HTTP (HAProxy)
    443   # HTTPS (HAProxy)
    4000  # Phoenix app (internal)
    5432  # PostgreSQL
    8123  # ClickHouse HTTP
    9000  # ClickHouse native
  ];

  # Journald configuration
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=2G
  '';
}
