# Oracle Cloud-specific configuration
# Handles Oracle Cloud Free Tier quirks:
# - Non-EFI boot (MBR GRUB)
# - Pre-existing partition layout (no disko)
# - Idle prevention (avoid instance reclamation)
{ config, pkgs, lib, ... }:

{
  # Filesystem configuration for Oracle Cloud (pre-existing partitions)
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "ext4";
    options = [ "x-initrd.mount" "defaults" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-main-boot";
    fsType = "vfat";
    options = [ "defaults" ];
  };

  # Boot loader configuration for Oracle Cloud
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";  # Oracle uses MBR GRUB on /dev/sda
    efiSupport = false;   # No EFI on Oracle Free Tier
  };

  # Boot-time rollback protection
  boot.loader.timeout = 10;  # Show boot menu for 10 seconds to select previous generation

  # Idle Prevention - prevent Oracle from reclaiming instance due to low utilization
  # Oracle reclaims when CPU/Memory/Network ALL < 20% for 7+ days
  # Solution: Generate periodic load every 5 minutes to keep metrics > 20%

  # Create idle prevention script - LIGHTWEIGHT VERSION
  # Uses gentle load to avoid conflicts with other services
  environment.etc."idle-prevention.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Idle Prevention Script - lightweight load generation
      # Designed to work alongside other services on resource-constrained systems

      LOG_FILE="/var/log/idle-prevention.log"
      mkdir -p "$(dirname "$LOG_FILE")"

      # Log start
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting idle prevention cycle" >> "$LOG_FILE"

      # Gentle CPU load: only 10 fibonacci ops (not 25)
      seq 1 10 | while read n; do
        echo "define f(x) { if (x<=1) return x; return f(x-1)+f(x-2) } f($n)" | ${pkgs.bc}/bin/bc > /dev/null 2>&1 &
      done
      wait

      # Light memory pressure: 50MB instead of 100MB
      ${pkgs.coreutils}/bin/dd if=/dev/zero of=/tmp/mem_test bs=1M count=50 2>/dev/null
      ${pkgs.coreutils}/bin/rm -f /tmp/mem_test

      # Network activity: single request (not multiple)
      ${pkgs.curl}/bin/curl -s "https://api.github.com/repos/github/gitignore" > /dev/null 2>&1 || true

      # Disk I/O: lightweight check
      ${pkgs.coreutils}/bin/du -sh / > /dev/null 2>&1

      # Log completion
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Idle prevention cycle complete" >> "$LOG_FILE"
    '';
  };

  # Systemd service for idle prevention (oneshot)
  systemd.services.idle-prevention = {
    description = "Oracle Idle Prevention - Generate load every 5 minutes";
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/etc/idle-prevention.sh";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "idle-prevention";
    };
  };

  # Systemd timer - run idle prevention every 5 minutes
  systemd.timers.idle-prevention = {
    description = "Trigger idle prevention every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20min";       # Start 20 minutes after boot (maximum safety)
      OnUnitActiveSec = "5min";  # Then every 5 minutes
      Persistent = true;         # Persistent across reboots
      AccuracySec = "1s";        # Run at exact time
    };
  };
}
