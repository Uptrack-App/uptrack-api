# HAProxy - Patroni-aware PostgreSQL primary proxy
# Routes PostgreSQL connections to the current Patroni primary automatically.
# Polls Patroni REST API (GET /master, port 8008): 200 = primary, 503 = standby.
# NOTE: /patroni returns 200 on ALL nodes (health ping). Use /master for role checks.
# Runs on coordinator nodes only (nbg1, nbg2).
#
# Architecture:
#   Phoenix → HAProxy (127.0.0.1:5000) → PgBouncer on primary (100.64.1.X:6432) → PostgreSQL
#
# Failover flow:
#   1. Patroni promotes nbg1 → GET /master on nbg1 returns 200, nbg2 returns 503
#   2. HAProxy health check detects change (every 2s)
#   3. HAProxy routes new connections to nbg1's PgBouncer
#   4. Ecto reconnects via pool checkout → app recovers automatically
#
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;
  coordinatorNodes = [ "nbg1" "nbg2" ];
  isCoordinator = builtins.elem nodeName coordinatorNodes;

  nodes = {
    nbg1 = "100.64.1.1";
    nbg2 = "100.112.11.29";
  };

in lib.mkIf isCoordinator {

  services.haproxy = {
    enable = true;

    config = ''
      global
        log /dev/log local0
        maxconn 200
        daemon

      defaults
        log     global
        mode    tcp
        option  tcplog
        option  dontlognull
        retries 3
        timeout connect 5s
        timeout client  10m
        timeout server  10m

      # PostgreSQL primary proxy (read-write connections)
      #
      # Health check uses HTTP against Patroni REST API:
      #   GET /master on port 8008 → 200 = primary only, 503 = standby
      # Data connections are TCP pass-through to PgBouncer on the primary node.
      #
      listen postgresql_primary
        bind 127.0.0.1:5000
        option  httpchk GET /master
        default-server inter 2s fall 2 rise 1 on-marked-down shutdown-sessions
        server  nbg1 ${nodes.nbg1}:6432 check port 8008
        server  nbg2 ${nodes.nbg2}:6432 check port 8008
    '';
  };

  # HAProxy must start after Tailscale (needs Tailscale IPs reachable)
  # and after Patroni (so health checks have something to query).
  systemd.services.haproxy = {
    after = [ "patroni.service" "tailscaled.service" "tailscale-autoconnect.service" ];
    wants = [ "patroni.service" ];

    serviceConfig = {
      Restart    = lib.mkForce "always";
      RestartSec = 5;
    };
  };
}
