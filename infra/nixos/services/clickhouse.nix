# ClickHouse Service Configuration
{ config, pkgs, lib, ... }:

{
  services.clickhouse = {
    enable = true;
  };

  # Open ClickHouse ports
  networking.firewall.allowedTCPPorts = [
    8123  # HTTP interface
    9000  # Native protocol
  ];
}
