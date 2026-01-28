# Oracle India Hyderabad - Regional Worker
# india-rworker: 144.24.150.48
# App-only + etcd (no PostgreSQL)
{ config, pkgs, lib, ... }:

let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64";
in {
  imports = [
    ../../../../common/base.nix
    ../../../../common/oracle.nix
    ../../../../modules/services/tailscale.nix
  ];

  # Basic system configuration (use lib.mkDefault to allow common.nix to override)
  system.stateVersion = lib.mkDefault "24.11";

  # Hostname
  networking.hostName = "uptrack-india-rworker";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "india-rworker";
    NODE_REGION = "asia";
    NODE_PROVIDER = "oracle";
    NODE_LOCATION = "india-hyderabad";
  };

  # Tailscale VPN configuration
  # This node will be known as "india-rworker" in the Tailscale network
  # Target static IP: 100.64.1.11 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "india-rworker";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
  };

  # Minimal packages - only essentials
  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
    htop
    tmux
    bc  # For idle prevention fibonacci calculations
  ];

  # User configuration - using root for simplicity
  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

  # Disable autologin
  services.getty.autologinUser = null;

  # Firewall - only SSH for minimal setup
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 4000 ];
  };

  # Journald configuration
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=2G
  '';

  # Boot-time rollback protection
  boot.loader.timeout = 10;  # Show boot menu for 10 seconds to select previous generation
}
