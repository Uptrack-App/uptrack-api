# Node A - Primary server (Hetzner)
{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "uptrack-node-a";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "node-a";
    NODE_REGION = "hetzner";
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
