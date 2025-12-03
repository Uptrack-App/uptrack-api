# Tailscale VPN Module
# Provides secure mesh networking across all infrastructure nodes
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.uptrack.tailscale;
in {
  options.services.uptrack.tailscale = {
    enable = mkEnableOption "Tailscale VPN for Uptrack infrastructure";

    authKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to file containing Tailscale auth key.
        The file should contain only the auth key (tskey-auth-...).
        For initial setup, you can pass the key via environment variable instead.
      '';
    };

    hostname = mkOption {
      type = types.str;
      description = ''
        Tailscale hostname for this node.
        Should be one of: eu-a, eu-b, eu-c, india-s, india-w
      '';
    };

    advertiseExitNode = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to advertise this node as an exit node";
    };

    acceptRoutes = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to accept subnet routes from other nodes";
    };

    tags = mkOption {
      type = types.listOf types.str;
      default = [ "tag:infrastructure" ];
      description = "Tailscale ACL tags for this node";
    };
  };

  config = mkIf cfg.enable {
    # Install Tailscale
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "both";  # Enable subnet routing and exit node features
    };

    # Trust the Tailscale interface completely (no firewall rules needed)
    networking.firewall = {
      trustedInterfaces = [ "tailscale0" ];

      # Allow Tailscale UDP port
      allowedUDPPorts = [ 41641 ];

      # Optionally allow Tailscale HTTPS (for MagicDNS)
      checkReversePath = "loose";  # Required for Tailscale
    };

    # Ensure Tailscale starts after network is online
    systemd.services.tailscaled = {
      after = [ "network-online.target" "systemd-resolved.service" ];
      wants = [ "network-online.target" ];
    };

    # Auto-connect on boot using auth key or existing credentials
    systemd.services.tailscale-autoconnect = {
      description = "Tailscale auto-connect on boot";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Check if already authenticated
        status=$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null || echo '{}')

        if echo "$status" | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
          echo "Tailscale already running and authenticated"

          # Update hostname if needed
          current_hostname=$(${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -r '.Self.HostName')
          if [ "$current_hostname" != "${cfg.hostname}" ]; then
            echo "Updating hostname to ${cfg.hostname}"
            ${pkgs.tailscale}/bin/tailscale set --hostname="${cfg.hostname}"
          fi

          exit 0
        fi

        echo "Tailscale not authenticated, attempting login..."

        # Build auth command
        AUTH_CMD="${pkgs.tailscale}/bin/tailscale up --hostname=${cfg.hostname}"

        ${optionalString cfg.acceptRoutes ''
          AUTH_CMD="$AUTH_CMD --accept-routes"
        ''}

        ${optionalString cfg.advertiseExitNode ''
          AUTH_CMD="$AUTH_CMD --advertise-exit-node"
        ''}

        ${optionalString (length cfg.tags > 0) ''
          AUTH_CMD="$AUTH_CMD --advertise-tags=${concatStringsSep "," cfg.tags}"
        ''}

        # Use auth key from file if provided
        ${optionalString (cfg.authKeyFile != null) ''
          if [ -f "${cfg.authKeyFile}" ]; then
            AUTH_KEY=$(cat "${cfg.authKeyFile}")
            AUTH_CMD="$AUTH_CMD --authkey=$AUTH_KEY"
          fi
        ''}

        # Use auth key from environment variable if available
        if [ -n "''${TAILSCALE_AUTHKEY:-}" ]; then
          AUTH_CMD="$AUTH_CMD --authkey=''${TAILSCALE_AUTHKEY}"
        fi

        echo "Executing: $AUTH_CMD (auth key hidden)"
        eval "$AUTH_CMD"

        # Wait for connection
        timeout=30
        while [ $timeout -gt 0 ]; do
          if ${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
            echo "Tailscale connected successfully"
            echo "Tailscale IP: $(${pkgs.tailscale}/bin/tailscale ip -4)"
            exit 0
          fi

          sleep 1
          timeout=$((timeout - 1))
        done

        echo "Warning: Tailscale connection timeout, but service will continue trying"
        exit 0
      '';
    };

    # Add helpful environment variables
    environment.variables = {
      TAILSCALE_HOSTNAME = cfg.hostname;
    };

    # Add Tailscale to system packages for easy CLI access
    environment.systemPackages = [ pkgs.tailscale ];
  };
}
