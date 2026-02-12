# Cloudflare Tunnel Module
# Provides public access to Phoenix API via Cloudflare's Zero Trust network
#
# Uses token-based authentication with remotely-managed ingress rules.
# The tunnel and routing (e.g., api.uptrack.dev → localhost:4000) are
# configured in the Cloudflare Zero Trust dashboard, not here.
#
# Setup:
#   1. Create tunnel in Cloudflare Zero Trust dashboard
#   2. Add public hostname: api.uptrack.dev → http://localhost:4000
#   3. Copy tunnel token, encrypt with agenix
#
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.cloudflared;
in {
  options.services.uptrack.cloudflared = {
    enable = mkEnableOption "Cloudflare Tunnel for public API access";

    package = mkOption {
      type = types.package;
      default = pkgs.cloudflared;
      description = "cloudflared package to use";
    };

    tunnelTokenFile = mkOption {
      type = types.path;
      description = ''
        Path to file containing the Cloudflare Tunnel token.
        For agenix, use: config.age.secrets.cloudflared-tunnel-token.path
      '';
      example = "/run/agenix/cloudflared-tunnel-token";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.cloudflared-tunnel = {
      description = "Cloudflare Tunnel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      script = ''
        TOKEN=$(cat ${cfg.tunnelTokenFile} | tr -d '[:space:]')
        exec ${cfg.package}/bin/cloudflared tunnel run --token "$TOKEN"
      '';

      serviceConfig = {
        Type = "simple";
        User = "cloudflared";
        Group = "cloudflared";
        Restart = "on-failure";
        RestartSec = "5s";

        # Timeouts
        TimeoutStartSec = "30s";
        TimeoutStopSec = "10s";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    users.users.cloudflared = {
      isSystemUser = true;
      group = "cloudflared";
    };

    users.groups.cloudflared = {};
  };
}
