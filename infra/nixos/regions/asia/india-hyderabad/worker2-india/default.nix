# Oracle Cloud India Hyderabad - Check Worker
# worker2-india: 152.67.179.42
# Tailscale: 100.96.28.118
# Role: Multi-region check worker (no DB, no Phoenix)
# Shape: VM.Standard.A1.Flex (3 OCPU ARM64, 18GB RAM)
{ config, pkgs, lib, ... }:

let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];
in {
  imports = [
    ./hardware-configuration.nix
    "${builtins.fetchTarball "https://github.com/nix-community/disko/archive/v1.11.0.tar.gz"}/module.nix"
    ./disk-config.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };
    initrd.systemd.enable = true;
  };

  # Hostname
  networking.hostName = "worker2-india";
  networking.networkmanager.enable = true;

  # Tailscale VPN
  services.tailscale.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };

  time.timeZone = "Asia/Kolkata";
  i18n.defaultLocale = "en_US.UTF-8";

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "without-password";
      PasswordAuthentication = false;
    };
  };

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
  users.users.le = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];
    openssh.authorizedKeys.keys = sshKeys;
  };
  security.sudo.extraRules = [
    { users = [ "le" ]; commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ]; }
  ];

  # Worker user
  users.users.uptrack-worker = {
    isSystemUser = true;
    group = "uptrack-worker";
    home = "/var/lib/uptrack-worker";
    createHome = true;
  };
  users.groups.uptrack-worker = {};

  # System packages
  environment.systemPackages = with pkgs; [
    elixir erlang git htop curl jq vim wget
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  documentation.enable = false;
  services.getty.autologinUser = null;

  # Uptrack Worker service
  systemd.services.uptrack-worker = {
    description = "Uptrack Worker - Regional Check Node (India)";
    after = [ "network.target" "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      MIX_ENV = "prod";
      RELEASE_COOKIE = "uptrack_prod_cookie";
      NODE_REGION = "asia";
      MAIN_NODES = "uptrack@100.64.1.1,uptrack@100.112.11.29";
      RELEASE_TMP = "/var/lib/uptrack-worker/tmp";
    };

    serviceConfig = {
      Type = "exec";
      User = "uptrack-worker";
      Group = "uptrack-worker";
      WorkingDirectory = "/var/lib/uptrack-worker";
      ExecStart = "/opt/uptrack-worker-release/bin/uptrack_worker start";
      ExecStop = "/opt/uptrack-worker-release/bin/uptrack_worker stop";
      Restart = "on-failure";
      RestartSec = "5s";
      TimeoutStartSec = "60s";
      TimeoutStopSec = "30s";
      MemoryMax = "2G";
      LimitNOFILE = 65536;
      NoNewPrivileges = true;
      PrivateTmp = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Journald
  services.journald.extraConfig = ''
    MaxRetentionSec=14day
    SystemMaxUse=2G
  '';

  boot.tmp.cleanOnBoot = true;
  boot.loader.timeout = 10;
  system.stateVersion = "24.11";
}
