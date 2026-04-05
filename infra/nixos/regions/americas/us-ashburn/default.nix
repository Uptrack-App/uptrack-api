# RackNerd US Ashburn - Check Worker
# worker1-us-ashburn: 204.152.220.248
# Tailscale: 100.69.152.35
# Role: Multi-region check worker (no DB, no Phoenix)
{ config, pkgs, lib, ... }:

let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICgQB4+99ONKRW1QC4815rDrlDlxLu1qTyBHeOQr2SsZ ghoangth@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];
in {
  imports = [
    ./hardware-configuration.nix
  ];

  # Hostname
  networking.hostName = "worker1-us-ashburn";

  # Tailscale VPN
  services.tailscale.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

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
    elixir erlang git htop curl jq
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Uptrack Worker service
  systemd.services.uptrack-worker = {
    description = "Uptrack Worker - Regional Check Node (US)";
    after = [ "network.target" "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      MIX_ENV = "prod";
      RELEASE_COOKIE = "uptrack_prod_cookie";
      NODE_REGION = "us";
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
      MemoryMax = "1800M";
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
  services.logrotate.checkConfig = false;
  system.stateVersion = "23.11";
}
