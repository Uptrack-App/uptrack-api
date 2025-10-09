# Node B - Secondary server (Contabo)
{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "uptrack-node-b";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "node-b";
    NODE_REGION = "contabo";
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
