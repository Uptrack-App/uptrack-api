# etcd - Distributed key-value store for Patroni coordination
# Runs on all 3 nodes for quorum (can tolerate 1 node failure)
{ config, pkgs, lib, ... }:

let
  # Get Tailscale IPs (these will be set after Tailscale is configured)
  # For initial setup, replace these with actual IPs after `tailscale ip -4`
  nodeATailscaleIP = "100.64.0.1";  # Replace after setup
  nodeBTailscaleIP = "100.64.0.2";  # Replace after setup
  nodeCTailscaleIP = "100.64.0.3";  # Replace after setup

  # Determine this node's name and IP
  nodeName = config.networking.hostName;
  nodeIP = if nodeName == "uptrack-node-a" then nodeATailscaleIP
           else if nodeName == "uptrack-node-b" then nodeBTailscaleIP
           else nodeCTailscaleIP;

in {
  services.etcd = {
    enable = true;
    name = nodeName;

    # Listen on Tailscale IP + localhost
    listenClientUrls = [
      "http://${nodeIP}:2379"
      "http://127.0.0.1:2379"
    ];
    listenPeerUrls = [ "http://${nodeIP}:2380" ];

    # Advertise Tailscale IPs to cluster
    advertiseClientUrls = [ "http://${nodeIP}:2379" ];
    initialAdvertisePeerUrls = [ "http://${nodeIP}:2380" ];

    # Cluster members
    initialCluster = [
      "uptrack-node-a=http://${nodeATailscaleIP}:2380"
      "uptrack-node-b=http://${nodeBTailscaleIP}:2380"
      "uptrack-node-c=http://${nodeCTailscaleIP}:2380"
    ];

    initialClusterState = "new";
    initialClusterToken = "uptrack-etcd-cluster";

    # Data directory
    dataDir = "/var/lib/etcd";
  };

  # Ensure etcd starts after Tailscale
  systemd.services.etcd = {
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
  };

  # No firewall rules needed - Tailscale handles it
}
