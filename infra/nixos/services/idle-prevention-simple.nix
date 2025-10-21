# Simple Idle Prevention for Oracle Always Free - Using systemd Timers
# Prevents instance reclamation by keeping CPU/Memory/Network > 20%
# Runs every 5 minutes via systemd timer (NixOS native approach)
{ config, pkgs, ... }:

let
  # Create idle prevention script using pkgs.writeShellScript
  idlePreventionScript = pkgs.writeShellScript "idle-prevention" ''
    #!/bin/sh
    # Simple idle prevention - generates CPU, memory, and network load

    LOG_FILE="/var/log/idle-prevention.log"
    mkdir -p "$(dirname "$LOG_FILE")"

    # Log timestamp
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting idle prevention cycle" >> "$LOG_FILE"

    # CPU load: fibonacci computation in bc
    seq 1 25 | while read n; do
      echo "define f(x) { if (x<=1) return x; return f(x-1)+f(x-2) } f($n)" | bc > /dev/null 2>&1 &
    done
    wait

    # Memory pressure: allocate memory via dd
    dd if=/dev/zero of=/tmp/mem_test bs=1M count=100 2>/dev/null
    rm -f /tmp/mem_test

    # Network activity: fetch data
    ${pkgs.curl}/bin/curl -s "https://api.github.com/users/github" > /dev/null 2>&1 || true

    # Disk I/O: write to log
    ${pkgs.coreutils}/bin/du -sh / > /dev/null 2>&1

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Idle prevention cycle complete" >> "$LOG_FILE"
  '';
in
{
  # Install required packages
  environment.systemPackages = with pkgs; [
    curl
    coreutils
    bc
  ];

  # Create systemd service for idle prevention
  systemd.services.idle-prevention = {
    description = "Oracle Idle Prevention - Generate load to prevent reclamation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${idlePreventionScript}";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "idle-prevention";
    };
  };

  # Create systemd timer to run every 5 minutes
  systemd.timers.idle-prevention = {
    description = "Trigger idle prevention every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";        # Start 1 minute after boot
      OnUnitActiveSec = "5min";  # Then every 5 minutes
      Persistent = true;         # Persistent across reboots
      AccuracySec = "1s";        # Run at exact time
    };
  };

  # Ensure log file directory exists
  systemd.tmpfiles.rules = [
    "d /var/log 0755 root root -"
    "f /var/log/idle-prevention.log 0644 root root -"
  ];
}
