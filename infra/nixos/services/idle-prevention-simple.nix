# Simple Idle Prevention for Oracle Always Free - Pure NixOS Approach
# Prevents instance reclamation by keeping CPU/Memory/Network > 20%
# Runs simple commands every 5 minutes via cron
{ config, pkgs, ... }:

{
  # Install required packages
  environment.systemPackages = with pkgs; [
    curl
    coreutils
    bc
  ];

  # Setup cron job for idle prevention
  services.cron.enable = true;

  # Create idle prevention script in /etc
  environment.etc."idle-prevention.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Simple idle prevention - generates CPU, memory, and network load

      # Log timestamp
      echo "[$(date)] Starting idle prevention cycle" >> /var/log/idle-prevention.log

      # CPU load: fibonacci computation in bc
      echo "Computing fibonacci..." >> /var/log/idle-prevention.log
      seq 1 25 | while read n; do
        echo "define f(x) { if (x<=1) return x; return f(x-1)+f(x-2) } f($n)" | bc > /dev/null 2>&1 &
      done
      wait

      # Memory pressure: allocate memory via dd
      echo "Memory pressure..." >> /var/log/idle-prevention.log
      dd if=/dev/zero of=/tmp/mem_test bs=1M count=100 2>/dev/null
      rm -f /tmp/mem_test

      # Network activity: fetch data
      echo "Network activity..." >> /var/log/idle-prevention.log
      curl -s "https://api.github.com/users/github" > /dev/null 2>&1 || true

      # Disk I/O: write to log
      du -sh / > /dev/null 2>&1

      echo "[$(date)] Idle prevention cycle complete" >> /var/log/idle-prevention.log
    '';
  };

  # Create cron job - every 5 minutes
  environment.etc."cron.d/idle-prevention" = {
    mode = "0644";
    text = ''
      # Run idle prevention every 5 minutes
      */5 * * * * root /bin/sh /etc/idle-prevention.sh >> /var/log/idle-prevention.log 2>&1
    '';
  };

  # Ensure log file exists and rotates
  systemd.tmpfiles.rules = [
    "f /var/log/idle-prevention.log 0644 root root -"
    "d /var/log 0755 root root -"
  ];
}
