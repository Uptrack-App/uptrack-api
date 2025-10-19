# Node India Weak - App-only + etcd member (Oracle Cloud Free Tier)
{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "uptrack-node-india-weak";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "india-weak";
    NODE_REGION = "ap-south";
  };

  # Open ports for services
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # HTTP (HAProxy)
    443   # HTTPS (HAProxy)
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
