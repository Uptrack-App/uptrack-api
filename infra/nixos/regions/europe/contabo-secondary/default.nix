# Contabo Secondary Node - Europe
# node-b: 185.237.12.64
# Worker profile (no HAProxy)
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../../common/base.nix
    ../../../common/contabo.nix
    ../../../modules/profiles/worker.nix
  ];

  # Hostname
  networking.hostName = "uptrack-contabo-secondary";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "contabo-secondary";
    NODE_REGION = "europe";
    NODE_PROVIDER = "contabo";
  };

  # Open ports for services
  networking.firewall.allowedTCPPorts = [
    22    # SSH
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
