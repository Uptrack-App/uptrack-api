# etcd - Distributed key-value store for Patroni coordination
# Runs on nbg1, nbg2, nbg3 for 3-node quorum (tolerates 1 node failure)
# Used by both Patroni clusters: "coordinator" (nbg1+nbg2) and "worker" (nbg3+nbg4)
{ config, pkgs, lib, ... }:

let
  # Tailscale IPs (static, assigned via Tailscale admin console)
  nodes = {
    nbg1 = "100.64.1.1";
    nbg2 = "100.64.1.2";
    nbg3 = "100.64.1.3";
  };

  nodeName = config.networking.hostName;
  isEtcdNode = builtins.hasAttr nodeName nodes;
  nodeIP = if isEtcdNode then nodes.${nodeName} else null;

in lib.mkIf isEtcdNode {
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
      "nbg1=http://${nodes.nbg1}:2380"
      "nbg2=http://${nodes.nbg2}:2380"
      "nbg3=http://${nodes.nbg3}:2380"
    ];

    initialClusterState = "new";
    initialClusterToken = "uptrack-etcd-cluster";

    # Data directory
    dataDir = "/var/lib/etcd";
  };

  # Ensure etcd starts after Tailscale
  systemd.services.etcd = {
    after = [ "tailscaled.service" "tailscale-autoconnect.service" ];
    requires = [ "tailscaled.service" ];

    serviceConfig = {
      # Fail fast if Tailscale isn't ready
      TimeoutStartSec = "60s";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # etcdctl convenience alias
  environment.systemPackages = [ pkgs.etcd ];
}
