# Stalwart outbound-only SMTP relay
# Accepts unauthenticated SMTP on localhost (and optionally Tailscale IP) and delivers outbound via MX.
# Used by the Uptrack SMTP fleet as the local mail relay on each API node.
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.stalwart;
  dkimKeyPath = "/var/lib/stalwart-mail/dkim/uptrack-app.key";
in
{
  options.services.uptrack.stalwart = {
    enable = mkEnableOption "Stalwart outbound SMTP relay for Uptrack";

    smtpPort = mkOption {
      type = types.port;
      default = 587;
      description = "SMTP submission port";
    };

    bindAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = ''
        IP addresses to bind the SMTP listener on.
        Include the node's Tailscale IP to allow the peer node to use this
        instance as an SMTP fallback (SMTP_FALLBACK_HOST).
      '';
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

    services.stalwart-mail = {
      enable = true;

      settings = {
        server.listener.smtp-submission = {
          bind = map (addr: "${addr}:${toString cfg.smtpPort}") cfg.bindAddresses;
          protocol = "smtp";
          tls.implicit = false;
        };

        # No authentication required — this is a trusted local relay.
        # Binding to localhost/Tailscale only ensures only our own processes connect.
        session.auth.require = false;
        session.auth.mechanisms = [ ];

        # Allow relay to any external recipient domain.
        session.rcpt.relay = true;

        # Disable spam filter — we're the sender, not a public-facing MX.
        spam-filter.enable = false;

        # DKIM signing for outbound mail.
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
      };
    };
  };
}
