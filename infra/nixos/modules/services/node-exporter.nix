# Prometheus Node Exporter
# Exposes host-level metrics (CPU, memory, disk, network) on port 9100.
# Deployed to all nodes. Scraped by vmagent.
#
# Port: 9100
#
{ config, pkgs, lib, ... }:

{
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "cpu"
      "diskstats"
      "filesystem"
      "loadavg"
      "meminfo"
      "netdev"
      "stat"
      "time"
      "uname"
      "systemd"
    ];
  };

  networking.firewall.allowedTCPPorts = [ 9100 ];
}
