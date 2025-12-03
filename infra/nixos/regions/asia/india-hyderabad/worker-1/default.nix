# Oracle India Hyderabad - Worker 1
# node-india-strong: 152.67.179.42
# PostgreSQL Replica (145 GB storage)
{ config, pkgs, lib, ... }:

let
  vars = {
    username = "le";
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICfp1F7sleNwU9YuAS/f7sdhH7cc0vHZ/kFsN3cPC18i";
  };
in {
  imports = [
    ../../../../common/base.nix
    ../../../../common/oracle.nix
    ../../../../modules/profiles/minimal.nix
    ../../../../modules/services/tailscale.nix
  ];

  # Hostname
  networking.hostName = "uptrack-india-hyderabad-1";

  # Node-specific environment variables
  environment.variables = {
    NODE_NAME = "india-hyderabad-1";
    NODE_REGION = "asia";
    NODE_PROVIDER = "oracle";
    NODE_LOCATION = "india-hyderabad";
  };

  # Tailscale VPN configuration
  # This node will be known as "india-s" (india-strong) in the Tailscale network
  # Target static IP: 100.64.1.10 (assigned via Tailscale admin console)
  services.uptrack.tailscale = {
    enable = true;
    hostname = "india-s";
    acceptRoutes = true;
    tags = [ "tag:infrastructure" ];
  };

  # Minimal packages - only essentials (bc needed for idle prevention)
  environment.systemPackages = with pkgs; [
    bc  # For idle prevention fibonacci calculations
  ];

  # User configuration (Oracle uses non-root user)
  users.mutableUsers = false;

  users.users.${vars.username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ vars.sshKey ];
    hashedPassword = "$6$rounds=65536$saltsaltlettuce$Lp/FV.2oOgew7GXTlwS/Lpyz90UeH8AgMFsN7K3MQFZWrhsQLSa2hjF6k5yHbAYlHBSJTCCZL5GpaTLMWL6N01";
  };

  users.users.root.openssh.authorizedKeys.keys = [ vars.sshKey ];

  # Disable autologin
  services.getty.autologinUser = null;

  # Firewall - only SSH and HTTP/HTTPS for application
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 4000 5432 ];
  };

  # PostgreSQL configuration overrides for Oracle Cloud
  # Use PostgreSQL 17 JIT for better performance on ARM64
  # Note: Data stored in /var/lib/postgresql (boot volume, 31GB available)
  services.postgresql = {
    package = lib.mkForce pkgs.postgresql_17_jit;

    # Automatically create database and user
    ensureDatabases = [ "uptrack" ];
    ensureUsers = [
      {
        name = "uptrack";
        ensureDBOwnership = true;
      }
    ];
  };

  # PostgreSQL starts AFTER SSH is ready (SSH always available first)
  systemd.services.postgresql = {
    after = [ "sshd.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  # Journald configuration
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=2G
  '';
}
