# Stalwart outbound-only SMTP relay
# Accepts unauthenticated SMTP on localhost (and optionally Tailscale IP) and delivers outbound via MX.
# Used by the Uptrack SMTP fleet as the local mail relay on each API node.
#
# Optional: external SMTPS submission on port 465 for Gmail "Send mail as".
# Requires DNS A record (smtp.uptrack.app → node IP) and Let's Encrypt cert.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.stalwart;
  ext = cfg.externalSubmission;
  dkimKeyPath = "/var/lib/stalwart-mail/dkim/uptrack-app.key";
in
{
  options.services.uptrack.stalwart = {
    enable = mkEnableOption "Stalwart outbound SMTP relay for Uptrack";

    smtpPort = mkOption {
      type = types.port;
      default = 587;
      description = "SMTP submission port (internal)";
    };

    bindAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = ''
        IP addresses to bind the internal SMTP listener on.
        Include the node's Tailscale IP to allow the peer node to use this
        instance as an SMTP fallback (SMTP_FALLBACK_HOST).
      '';
    };

    externalSubmission = {
      enable = mkEnableOption "External SMTPS submission (for Gmail Send-as)";

      hostname = mkOption {
        type = types.str;
        default = "smtp.uptrack.app";
        description = "Hostname for TLS certificate (must have A record to this node).";
      };

      port = mkOption {
        type = types.port;
        default = 465;
        description = "SMTPS submission port (implicit TLS).";
      };

      username = mkOption {
        type = types.str;
        default = "uptrack";
        description = "Username for SMTP authentication.";
      };

      passwordFile = mkOption {
        type = types.path;
        description = "Path to file containing the SMTP auth password.";
      };
    };

    dkimDomain = mkOption {
      type = types.str;
      default = "uptrack.app";
      description = "Domain to sign outbound mail with DKIM.";
    };

    dkimSelector = mkOption {
      type = types.str;
      default = "stalwart";
      description = "DKIM selector. DNS record will be at <selector>._domainkey.<domain>.";
    };
  };

  config = mkIf cfg.enable {
    # Deploy the DKIM private key to the expected path.
    systemd.tmpfiles.rules = [
      "d /var/lib/stalwart-mail/dkim 0750 stalwart-mail stalwart-mail -"
    ];

    systemd.services.stalwart-mail.preStart = ''
      if [ ! -f ${dkimKeyPath} ]; then
        echo "WARNING: DKIM private key not found at ${dkimKeyPath}. DKIM signing will fail."
      fi
    '';

    # Open SMTPS port in firewall when external submission is enabled
    networking.firewall.allowedTCPPorts = mkIf ext.enable [ ext.port ];

    # fail2ban: ban IPs after 5 failed SMTP auth attempts in 10 minutes
    services.fail2ban = mkIf ext.enable {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      jails.stalwart-smtp = {
        settings = {
          enabled = true;
          port = toString ext.port;
          filter = "stalwart-smtp";
          logpath = "/var/log/stalwart-mail/stalwart-mail.log";
          maxretry = 5;
          findtime = 600;
          bantime = 3600;
        };
      };
    };

    environment.etc."fail2ban/filter.d/stalwart-smtp.conf" = mkIf ext.enable {
      text = ''
        [Definition]
        failregex = ^.*Authentication failed.*remote_ip=<HOST>.*$
        ignoreregex =
      '';
    };

    # Let's Encrypt cert for SMTP TLS (DNS-01 challenge via Cloudflare)
    security.acme = mkIf ext.enable {
      acceptTerms = true;
      defaults.email = "hoangbytes@gmail.com";
      certs.${ext.hostname} = {
        dnsProvider = "cloudflare";
        environmentFile = config.age.secrets.cloudflare-api-token.path;
        group = "stalwart-mail";
      };
    };

    services.stalwart-mail = {
      enable = true;

      settings = let
        certDir = if ext.enable
          then config.security.acme.certs.${ext.hostname}.directory
          else "/dev/null";
      in {
        # ── Listeners ──────────────────────────────────────────────

        # Internal: localhost + Tailscale, no TLS, no auth
        server.listener."smtp-internal" = {
          bind = map (addr: "${addr}:${toString cfg.smtpPort}") cfg.bindAddresses;
          protocol = "smtp";
          tls.implicit = false;
        };

        # ── Auth (conditional per listener) ────────────────────────
        # Internal listener: no auth required
        # External listener: auth required with PLAIN + LOGIN
        session.auth.mechanisms = if ext.enable
          then [
            { "if" = "listener != 'smtps-external'"; "then" = false; }
            { "else" = "[plain, login]"; }
          ]
          else [];

        session.auth.require = if ext.enable
          then [
            { "if" = "listener != 'smtps-external'"; "then" = false; }
            { "else" = true; }
          ]
          else false;

        session.auth.directory = if ext.enable
          then [
            { "if" = "listener = 'smtps-external'"; "then" = "'gmail-relay'"; }
            { "else" = false; }
          ]
          else false;

        session.auth.must-match-sender = false;
        session.auth.allow-plain-text = false;
        session.auth.errors.total = 3;
        session.auth.errors.wait = "5s";

        # ── Relay ──────────────────────────────────────────────────
        session.rcpt.relay = true;

        # Disable spam filter — we're the sender, not a public-facing MX.
        spam-filter.enable = false;

        # ── DKIM signing ───────────────────────────────────────────
        signature."rsa" = {
          private-key = "%{file:${dkimKeyPath}}%";
          domain = cfg.dkimDomain;
          selector = cfg.dkimSelector;
          headers = [
            "From" "To" "Cc" "Date" "Subject" "Message-ID"
            "MIME-Version" "Content-Type" "In-Reply-To" "References"
          ];
          algorithm = "rsa-sha256";
          canonicalization = "relaxed/relaxed";
          expire = "10d";
          set-body-length = false;
          report = true;
        };

        auth.dkim.sign = "['rsa']";
      }
      # ── External submission (conditional) ─────────────────────
      // (optionalAttrs ext.enable {
        # SMTPS listener: public, implicit TLS, auth required
        server.listener."smtps-external" = {
          bind = [ "[::]:${toString ext.port}" ];
          protocol = "smtp";
          tls.implicit = true;
          tls.certificate = "acme";
        };

        # TLS certificate from Let's Encrypt
        certificate."acme" = {
          cert = "%{file:${certDir}/fullchain.pem}%";
          private-key = "%{file:${certDir}/key.pem}%";
        };

        # Static user directory for Gmail Send-as auth
        directory."gmail-relay" = {
          type = "memory";
          principals = [
            {
              class = "individual";
              name = ext.username;
              secret = "%{file:${ext.passwordFile}}%";
              email = [ "hello@uptrack.app" "team@uptrack.app" "alerts@uptrack.app" ];
            }
          ];
        };

        # Use gmail-relay directory for auth lookups
        storage.directory = "gmail-relay";
      });
    };
  };
}
