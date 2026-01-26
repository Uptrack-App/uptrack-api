# Tailscale VPN Module
# Provides secure mesh networking across all infrastructure nodes
#
# Authentication options (in order of preference):
#   1. authKeyFile - Path to file with auth key (recommended for agenix)
#   2. TAILSCALE_AUTHKEY env var - For manual/CI deployment
#   3. Already authenticated - Node rejoins automatically
#
# Auth key is ONLY needed for first-time join. Once authenticated,
# credentials are stored in /var/lib/tailscale and persist across reboots.
#
# To create an auth key:
#   1. Go to https://login.tailscale.com/admin/settings/keys
#   2. Click "Generate auth key..."
#   3. Enable "Reusable" for multiple nodes
#   4. Enable "Pre-approved" to skip admin approval
#   5. Set tags (e.g., tag:infrastructure)
#
# For long-term automation, create an OAuth client:
#   1. Go to Settings → OAuth clients
#   2. Create client with "devices:write" scope
#   3. Use client secret as auth key (tskey-client-...)
#
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
        Path to file containing Tailscale auth key or OAuth client secret.
        Supports both formats:
          - Auth key: tskey-auth-xxxxx (expires after 90 days max)
          - OAuth client secret: tskey-client-xxxxx (never expires)

        For agenix, use: config.age.secrets.tailscale-authkey.path

        Note: Only needed for first-time join. Once authenticated,
        the node will reconnect automatically without the key.
      '';
      example = "/run/agenix/tailscale-authkey";
    };

    hostname = mkOption {
      type = types.str;
      description = "Tailscale hostname for this node (e.g., nbg1, nbg2)";
      example = "nbg1";
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

    servePort = mkOption {
      type = types.nullOr types.port;
      default = null;
      description = ''
        Port to advertise via Tailscale Services.
        When set, this node will run `tailscale serve tcp:<port>` to advertise
        the service for load balancing and automatic failover.
      '';
      example = 4000;
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
        backend_state=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.BackendState // "Unknown"')

        echo "Tailscale backend state: $backend_state"

        if [ "$backend_state" = "Running" ]; then
          echo "✓ Tailscale already authenticated and running"

          # Update hostname if needed
          current_hostname=$(echo "$status" | ${pkgs.jq}/bin/jq -r '.Self.HostName // "unknown"')
          if [ "$current_hostname" != "${cfg.hostname}" ]; then
            echo "Updating hostname: $current_hostname → ${cfg.hostname}"
            ${pkgs.tailscale}/bin/tailscale set --hostname="${cfg.hostname}"
          fi

          echo "Tailscale IP: $(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null || echo 'not assigned yet')"
          exit 0
        fi

        echo "Tailscale not authenticated, attempting login..."

        # Build auth command
        AUTH_CMD="${pkgs.tailscale}/bin/tailscale up --hostname=${cfg.hostname} --reset"

        ${optionalString cfg.acceptRoutes ''
          AUTH_CMD="$AUTH_CMD --accept-routes"
        ''}

        ${optionalString cfg.advertiseExitNode ''
          AUTH_CMD="$AUTH_CMD --advertise-exit-node"
        ''}

        ${optionalString (length cfg.tags > 0) ''
          AUTH_CMD="$AUTH_CMD --advertise-tags=${concatStringsSep "," cfg.tags}"
        ''}

        # Check for auth key (file takes precedence over env var)
        AUTH_KEY=""

        ${optionalString (cfg.authKeyFile != null) ''
          if [ -f "${cfg.authKeyFile}" ]; then
            AUTH_KEY=$(cat "${cfg.authKeyFile}" | tr -d '[:space:]')
            echo "Using auth key from file: ${cfg.authKeyFile}"
          else
            echo "Warning: Auth key file not found: ${cfg.authKeyFile}"
          fi
        ''}

        # Fall back to environment variable
        if [ -z "$AUTH_KEY" ] && [ -n "''${TAILSCALE_AUTHKEY:-}" ]; then
          AUTH_KEY="''${TAILSCALE_AUTHKEY}"
          echo "Using auth key from TAILSCALE_AUTHKEY environment variable"
        fi

        # Add auth key to command if available
        if [ -n "$AUTH_KEY" ]; then
          AUTH_CMD="$AUTH_CMD --authkey=$AUTH_KEY"
          echo "Executing tailscale up with auth key (key hidden for security)"
        else
          echo "Warning: No auth key provided. If this is a new node, authentication will fail."
          echo "Provide auth key via:"
          echo "  1. authKeyFile option (recommended for agenix)"
          echo "  2. TAILSCALE_AUTHKEY environment variable"
          echo "Attempting connection anyway (will work if previously authenticated)..."
        fi

        # Execute the command
        eval "$AUTH_CMD" || {
          echo "tailscale up failed. Check if auth key is valid or if node was previously authenticated."
          exit 1
        }

        # Wait for connection
        echo "Waiting for Tailscale connection..."
        timeout=60
        while [ $timeout -gt 0 ]; do
          if ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
            echo "✓ Tailscale connected successfully"
            echo "Tailscale IP: $(${pkgs.tailscale}/bin/tailscale ip -4)"
            echo "Hostname: ${cfg.hostname}"
            exit 0
          fi

          sleep 1
          timeout=$((timeout - 1))
        done

        echo "Warning: Tailscale connection timeout after 60s"
        echo "The service will continue retrying in the background"
        exit 0
      '';
    };

    # Add helpful environment variables
    environment.variables = {
      TAILSCALE_HOSTNAME = cfg.hostname;
    };

    # Add Tailscale to system packages for easy CLI access
    environment.systemPackages = [ pkgs.tailscale ];

    # Tailscale Serve for service advertisement (load balancing)
    systemd.services.tailscale-serve = mkIf (cfg.servePort != null) {
      description = "Tailscale Serve - advertise service for load balancing";
      after = [ "network-online.target" "tailscale-autoconnect.service" ];
      wants = [ "network-online.target" "tailscale-autoconnect.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg tcp:${toString cfg.servePort}";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve off";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      # Wait for Tailscale to be fully connected before serving
      preStart = ''
        timeout=60
        while [ $timeout -gt 0 ]; do
          if ${pkgs.tailscale}/bin/tailscale status --json | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' > /dev/null 2>&1; then
            echo "Tailscale connected, starting serve..."
            exit 0
          fi
          sleep 1
          timeout=$((timeout - 1))
        done
        echo "Warning: Tailscale not fully connected, attempting serve anyway"
      '';
    };
  };
}
