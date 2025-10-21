# Simple Idle Prevention for Oracle Always Free - Pure NixOS Approach
# Prevents instance reclamation by keeping CPU/Memory/Network > 20%
# Runs simple commands every 5 minutes via cron
{ config, pkgs, ... }:

let
  # Create idle prevention script using pkgs.writeShellScript
  idlePreventionScript = pkgs.writeShellScript "idle-prevention" ''
    #!/bin/sh
    # Simple idle prevention - generates CPU, memory, and network load

    LOG_FILE="/var/log/idle-prevention.log"

    # Log timestamp
    echo "[$(date)] Starting idle prevention cycle" >> "$LOG_FILE"

    # CPU load: fibonacci computation in bc
    echo "Computing fibonacci..." >> "$LOG_FILE"
    seq 1 25 | while read n; do
      echo "define f(x) { if (x<=1) return x; return f(x-1)+f(x-2) } f($n)" | bc > /dev/null 2>&1 &
    done
    wait

    # Memory pressure: allocate memory via dd
    echo "Memory pressure..." >> "$LOG_FILE"
    dd if=/dev/zero of=/tmp/mem_test bs=1M count=100 2>/dev/null
    rm -f /tmp/mem_test

    # Network activity: fetch data
    echo "Network activity..." >> "$LOG_FILE"
    ${pkgs.curl}/bin/curl -s "https://api.github.com/users/github" > /dev/null 2>&1 || true

    # Disk I/O: write to log
    ${pkgs.coreutils}/bin/du -sh / > /dev/null 2>&1

    echo "[$(date)] Idle prevention cycle complete" >> "$LOG_FILE"
  '';
in
{
  # Install required packages + idle prevention script
  environment.systemPackages = (with pkgs; [
    curl
    coreutils
    bc
  ]) ++ [
    idlePreventionScript
  ];

  # Setup cron job for idle prevention
  services.cron.enable = true;

  # Setup the cron job via environment.etc
  environment.etc."cron.d/idle-prevention" = {
    mode = "0644";
    text = ''
      # Run idle prevention every 5 minutes
      */5 * * * * root ${idlePreventionScript} >> /var/log/idle-prevention.log 2>&1
    '';
  };

  # Ensure log file exists
  systemd.tmpfiles.rules = [
    "f /var/log/idle-prevention.log 0644 root root -"
  ];
}
