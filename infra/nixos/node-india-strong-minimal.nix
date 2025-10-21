# India Strong - Minimal Configuration (Oracle Cloud Free Tier ARM64)
# Based on mtlynch's proven approach for Oracle Cloud
{ config, pkgs, lib, ... }:

let
  vars = {
    username = "le";
    sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICfp1F7sleNwU9YuAS/f7sdhH7cc0vHZ/kFsN3cPC18i";
  };
in {
  imports = [
    # Include only the base node config (hardware, disk)
    ./node-india-strong.nix
  ];

  # Basic system configuration (use lib.mkDefault to allow common.nix to override)
  system.stateVersion = lib.mkDefault "24.11";

  # Minimal packages - only essentials
  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
    htop
    tmux
  ];

  # User configuration
  users = {
    mutableUsers = false;
    users.${vars.username} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ vars.sshKey ];
      hashedPassword = "$6$rounds=65536$saltsaltlettuce$Lp/FV.2oOgew7GXTlwS/Lpyz90UeH8AgMFsN7K3MQFZWrhsQLSa2hjF6k5yHbAYlHBSJTCCZL5GpaTLMWL6N01";
    };
    users.root = {
      openssh.authorizedKeys.keys = [ vars.sshKey ];
    };
  };

  # SSH configuration (handled by common.nix)
  # services.openssh already configured in common.nix

  # Disable autologin
  services.getty.autologinUser = null;

  # Firewall - only SSH and HTTP/HTTPS for application
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 4000 5432 ];
  };

  # PostgreSQL - required for Uptrack (using 17.5 JIT for better performance)
  # Note: Data stored in /var/lib/postgresql (boot volume, 31GB available)
  # For production: consider attaching Oracle block volume and mounting at /var/lib/postgresql
  # Approach: Simple, let NixOS handle it (like terra project does)
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17_jit;  # PostgreSQL 17.5 with JIT compilation for performance
    enableTCPIP = true;

    settings = {
      max_connections = 100;
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      work_mem = "16MB";
      maintenance_work_mem = "64MB";
    };

    # Automatically create database and user
    ensureDatabases = [ "uptrack" ];
    ensureUsers = [
      {
        name = "uptrack";
        ensureDBOwnership = true;
      }
    ];

    authentication = pkgs.lib.mkOverride 10 ''
      # TYPE  DATABASE        USER            ADDRESS                 METHOD
      local   all             all                                     trust
      host    all             all             127.0.0.1/32            md5
      host    all             all             ::1/128                 md5
    '';
  };

  # PostgreSQL starts AFTER SSH is ready (SSH always available first)
  systemd.services.postgresql = {
    # Start AFTER SSH daemon is ready
    after = [ "sshd.service" "network-online.target" ];
    # Still auto-start on boot, but after SSH
    wantedBy = [ "multi-user.target" ];
    # No custom timeouts - let PostgreSQL take the time it needs
    # No Restart/RestartSec - just start normally
  };

  # Boot-time rollback protection
  boot.loader.timeout = 10;  # Show boot menu for 10 seconds to select previous generation

  # NO CLICKHOUSE - too resource intensive for Oracle Free Tier (leave for later)
  # NO UPTRACK SERVICE MODULE - deployed as release instead
}
