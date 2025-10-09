# HAProxy - Load balancer for HTTPS and Database routing
# Runs on all 3 nodes
{ config, pkgs, lib, ... }:

let
  nodeName = config.networking.hostName;

  # Tailscale IPs
  nodeATailscaleIP = "100.64.0.1";
  nodeBTailscaleIP = "100.64.0.2";

in {
  # ACME for automatic HTTPS certificates
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@uptrack.app";  # Change this

    certs."uptrack.app" = {
      domain = "uptrack.app";
      group = "haproxy";
      webroot = "/var/lib/acme/acme-challenge";

      # Combine cert and key for HAProxy
      postRun = ''
        CERT_DIR="/var/lib/acme/uptrack.app"
        cat "$CERT_DIR/fullchain.pem" "$CERT_DIR/key.pem" > "$CERT_DIR/combined.pem"
        chmod 640 "$CERT_DIR/combined.pem"
        chown acme:haproxy "$CERT_DIR/combined.pem"
        ${pkgs.systemd}/bin/systemctl reload haproxy.service || true
      '';
    };
  };

  # HAProxy service
  services.haproxy = {
    enable = true;

    config = ''
      defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        option  http-server-close
        option  forwardfor except 127.0.0.0/8
        option  redispatch
        retries 3
        timeout connect 5000
        timeout client  50000
        timeout server  50000

      # Frontend: HTTP (redirect to HTTPS + ACME challenges)
      frontend http_frontend
        bind *:80
        mode http

        # ACME HTTP-01 challenge
        acl is_acme_challenge path_beg /.well-known/acme-challenge/
        use_backend acme_backend if is_acme_challenge

        # Redirect all other HTTP to HTTPS
        http-request redirect scheme https code 301 if !is_acme_challenge

      # Frontend: HTTPS
      frontend https_frontend
        bind *:443 ssl crt /var/lib/acme/uptrack.app/combined.pem alpn h2,http/1.1
        mode http

        # Security headers
        http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        http-response set-header X-Content-Type-Options "nosniff"
        http-response set-header X-Frame-Options "SAMEORIGIN"
        http-response set-header X-XSS-Protection "1; mode=block"

        # Don't log health checks
        acl is_health_check path /healthz
        http-request set-log-level silent if is_health_check

        default_backend phoenix_backend

      # Backend: ACME challenges
      backend acme_backend
        mode http
        server acme_server 127.0.0.1:8080

      # Backend: Phoenix application (local)
      backend phoenix_backend
        mode http
        balance roundrobin
        option httpchk GET /healthz
        http-check expect status 200

        server local 127.0.0.1:4000 check inter 5s fall 3 rise 2

      # Frontend: Database proxy (local only, routes to Patroni primary)
      frontend postgres_primary
        bind 127.0.0.1:6432
        mode tcp
        option tcplog
        default_backend postgres_cluster

      # Backend: Postgres cluster (via Patroni health checks)
      backend postgres_cluster
        mode tcp
        option tcp-check

        # Patroni REST API health checks
        option httpchk
        http-check send meth GET uri /primary
        http-check expect status 200

        # Node A - Primary candidate
        server node-a ${nodeATailscaleIP}:5432 check port 8008 inter 5s fall 3 rise 2

        # Node B - Replica (backup)
        server node-b ${nodeBTailscaleIP}:5432 check port 8008 inter 5s fall 3 rise 2 backup

      # Stats page (localhost only)
      listen stats
        bind 127.0.0.1:8404
        mode http
        stats enable
        stats uri /stats
        stats refresh 30s
        stats auth admin:CHANGE_ME_STATS_PASSWORD
    '';
  };

  # Simple HTTP server for ACME challenges
  systemd.services.acme-challenge-server = {
    description = "Simple HTTP server for ACME challenges";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      User = "acme";
      Group = "acme";
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --directory /var/lib/acme/acme-challenge";
      Restart = "on-failure";
    };
  };

  # Create directories
  systemd.tmpfiles.rules = [
    "d /var/lib/acme/acme-challenge 0755 acme acme -"
    "d /var/lib/haproxy 0750 haproxy haproxy -"
    "d /run/haproxy 0750 haproxy haproxy -"
  ];

  # Open HTTP/HTTPS ports
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
