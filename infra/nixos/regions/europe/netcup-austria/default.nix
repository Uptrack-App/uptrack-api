# Netcup Austria - PostgreSQL Replica + VictoriaMetrics Node
# Tailscale IP: 100.64.0.2
# 6 vCPU, 8 GB RAM, 256 GB Storage
{ config, pkgs, lib, ... }:

{
  imports = [
    ../../../common/base.nix
    ../../../common/netcup.nix
    ../../../modules/profiles/worker.nix
  ];

  # Hostname
  networking.hostName = "uptrack-austria";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "austria";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "austria";

    # Database roles
    POSTGRES_ROLE = "replica";
    # TODO: Add VictoriaMetrics role

    # Tailscale
    TAILSCALE_IP = "100.64.0.2";
  };

  # Open ports for services
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    80    # HTTP
    443   # HTTPS
    4000  # Phoenix app
    5432  # PostgreSQL
    8008  # Patroni REST API
    # TODO: Add VictoriaMetrics ports
    
    2379  # etcd client
    2380  # etcd peer
  ];

  # Journald configuration
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=4G
  '';
}
