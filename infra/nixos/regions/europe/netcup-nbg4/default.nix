# Netcup Nuremberg Node 4 (nbg4) - Citus Worker Standby
# IP: 159.195.56.242
# Tailscale: 100.72.224.65
# Services: PostgreSQL Worker Standby, Patroni (worker), victoria-metrics
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64";
in {
  imports = [
    ../../../common/base.nix
    ../../../common/netcup.nix
    ../../../modules/services/tailscale.nix
    ../../../modules/services/patroni.nix
    ../../../modules/services/node-exporter.nix
    ../../../modules/services/postgres-exporter.nix
    ../../../modules/services/victoria-metrics.nix
  ];

  # ── invoice9 host setup ───────────────────────────────────────────────────
  # invoice9 runs as a systemd-nspawn container via extra-container.
  # After deploying this config, run from the invoice9 repo:
  #   nix run github:2folk/invoice9#container -- create --start
  # Updates: nix run github:2folk/invoice9#container -- create --start --restart-changed

  # extra-container CLI — needed to deploy/update the invoice9 container
  programs.extra-container.enable = true;

  # NAT for container outbound internet (Shopify API, Google Drive, etc.)
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];  # matches all container veth interfaces
    externalInterface = "ens3";       # nbg4's public interface (verified via `ip route`)
  };

  # Agenix secret: decrypted to /run/agenix/invoice9-env, bind-mounted read-only into container
  age.secrets.invoice9-env = {
    file = ../../../secrets/invoice9-env.age;
    mode = "0400";
  };

  # WC service env (dedicated DATABASE_URL_WC, Woo SaaS Billing API secret).
  # Bind-mounted read-only into the invoice9-wc container.
  age.secrets.invoice9-wc-env = {
    file = ../../../secrets/invoice9-wc-env.age;
    mode = "0400";
  };

  # Cloudflare API token for invoice9 ACME (dedicated token, DNS:Edit on 2folk.com)
  age.secrets.invoice9-cloudflare-token = {
    file = ../../../secrets/invoice9-cloudflare-token.age;
    mode = "0400";
  };

  # TLS certificates via Cloudflare DNS-01 — both primary domains share the
  # same ACME setup; one cert per hostname.
  security.acme = {
    acceptTerms = true;
    defaults.email = "le@2folk.com";
    certs."invoice9.2folk.com" = {
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.invoice9-cloudflare-token.path;
      group = "haproxy";
      postRun = ''
        cat fullchain.pem key.pem > haproxy.pem
        chown acme:haproxy haproxy.pem
        chmod 640 haproxy.pem
      '';
    };
    certs."invoice9-wc.2folk.com" = {
      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.invoice9-cloudflare-token.path;
      group = "haproxy";
      postRun = ''
        cat fullchain.pem key.pem > haproxy.pem
        chown acme:haproxy haproxy.pem
        chmod 640 haproxy.pem
      '';
    };
  };

  # HAProxy: HTTP→HTTPS redirect + TLS termination, two domains:
  #   invoice9.2folk.com    → 192.168.100.2:3001    (Shopify backend)
  #   invoice9-wc.2folk.com → 192.168.101.2:3001   (WooCommerce backend)
  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0
        maxconn 1000
        daemon

      defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        option  forwardfor
        timeout connect 5s
        timeout client  30s
        timeout server  30s

      frontend http-in
        bind *:80
        redirect scheme https code 301 if !{ ssl_fc }

      frontend https-in
        bind *:443 ssl crt /var/lib/acme/invoice9.2folk.com/haproxy.pem crt /var/lib/acme/invoice9-wc.2folk.com/haproxy.pem
        http-request set-header X-Forwarded-Proto https
        acl is_invoice9_wc hdr(host) -i invoice9-wc.2folk.com
        use_backend invoice9_wc if is_invoice9_wc
        default_backend invoice9

      backend invoice9
        option httpchk
        http-check send meth GET uri /health ver HTTP/1.1 hdr Host invoice9.2folk.com
        http-check expect status 200
        server invoice9 192.168.100.2:3001 check inter 10s

      backend invoice9_wc
        option httpchk
        http-check send meth GET uri /health ver HTTP/1.1 hdr Host invoice9-wc.2folk.com
        http-check expect status 200
        server invoice9_wc 192.168.101.2:3001 check inter 10s
    '';
  };

  systemd.services.haproxy = {
    after = [
      "acme-finished-invoice9.2folk.com.target"
      "acme-finished-invoice9-wc.2folk.com.target"
    ];
    wants = [
      "acme-finished-invoice9.2folk.com.target"
      "acme-finished-invoice9-wc.2folk.com.target"
    ];
  };

  # Container reaches Patroni (worker cluster: nbg3/nbg4) directly over Tailscale.
  # The multi-host DATABASE_URL in invoice9-env.age uses target_session_attrs=read-write
  # so the driver auto-selects the current leader — no per-node DNAT here, no need
  # to update this file on failover.
  networking.firewall.extraCommands = ''
    iptables -t nat -A POSTROUTING -o tailscale0 -s 192.168.100.0/24 -j MASQUERADE
    iptables -t nat -A POSTROUTING -o tailscale0 -s 192.168.101.0/24 -j MASQUERADE
  '';

  # Bring up host-side veth for the invoice9-wc container. Mirror of the
  # existing invoice9-veth-setup pattern — without this the chicken-and-egg
  # bites: container can't finish booting (migrations need DB) and the
  # native ExecStartPost network setup runs only after the container
  # signals ready, which it never does.
  systemd.services.invoice9-wc-veth-setup = {
    description = "Bring up ve-invoice9-wc veth for invoice9-wc container DB access";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "1";
      ExecStart = "${pkgs.bash}/bin/bash -c 'while true; do if ${pkgs.iproute2}/bin/ip link show ve-invoice9-wc > /dev/null 2>&1; then ${pkgs.iproute2}/bin/ip link set dev ve-invoice9-wc up 2>/dev/null || true; ${pkgs.iproute2}/bin/ip route add local 192.168.101.1 dev ve-invoice9-wc 2>/dev/null || true; ${pkgs.iproute2}/bin/ip route add 192.168.101.2 dev ve-invoice9-wc 2>/dev/null || true; echo 1 > /proc/sys/net/ipv4/conf/ve-invoice9-wc/proxy_arp 2>/dev/null || true; fi; sleep 1; done'";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Hostname
  networking.hostName = "nbg4";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "nbg4";
    NODE_REGION = "europe";
    NODE_PROVIDER = "netcup";
    NODE_LOCATION = "nuremberg";
  };

  # Tailscale VPN configuration
  # Static IP: 100.72.224.65 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "nbg4";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
  };

  # VictoriaMetrics single-node instance
  # HA: independent instance, vmagent writes to both nbg3+nbg4
  services.uptrack.victoria-metrics = {
    enable = true;
    retentionPeriod = "15";
  };

  # User configuration
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # System state version
  system.stateVersion = "24.11";
}
