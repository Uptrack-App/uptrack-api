# Idle Prevention Service for Oracle Always Free Instances
# Generates periodic CPU, memory, network, and disk I/O to prevent instance reclamation
# Oracle reclaims instances when: CPU/Memory/Network < 20% for 7+ days
{ config, pkgs, lib, ... }:

{
  systemd.services.idle-prevention = {
    description = "Oracle Idle Prevention - Generate sustained resource activity";

    after = [ "network-online.target" "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.bash}/bin/bash /usr/local/bin/idle-prevention.sh";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "idle-prevention";
    };
  };

  # Run every 5 minutes to generate load
  systemd.timers.idle-prevention = {
    description = "Trigger idle prevention every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };

  # Install the idle prevention script
  environment.etc."idle-prevention.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Idle Prevention Script for Oracle Always Free
      # Generates CPU, memory, network, and disk I/O activity
      # Runs every 5 minutes to keep utilization > 20%

      LOG_FILE="/var/log/idle-prevention.log"
      TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

      log_message() {
        echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
      }

      # ============================================================================
      # CPU Load Generation - Fibonacci computation
      # ============================================================================
      generate_cpu_load() {
        local start=$(date +%s%N | cut -b1-13)

        log_message "Generating CPU load..."

        # Compute fibonacci numbers in parallel
        for i in {1..4}; do
          (
            # CPU-intensive work: fibonacci computation
            python3 -c "
            def fib(n):
              if n <= 1:
                return n
              a, b = 0, 1
              for _ in range(n):
                a, b = b, a + b
              return a

            # Compute several large fibonacci numbers
            for i in range(1000, 1010):
              result = fib(i)
            " &
          ) &
        done

        wait

        local end=$(date +%s%N | cut -b1-13)
        local elapsed=$((end - start))
        log_message "CPU load completed in ''${elapsed}ms"
      }

      # ============================================================================
      # Memory Pressure Generation
      # ============================================================================
      generate_memory_pressure() {
        log_message "Generating memory pressure..."

        # Allocate and process ~200MB of memory
        python3 << 'PYTHON_EOF'
      import hashlib
      import time

      # Allocate 200MB chunks and process them
      for chunk_num in range(4):
          # Allocate 50MB
          data = bytearray(50 * 1024 * 1024)

          # Do some work with it
          for i in range(0, len(data), 1024):
              data[i:i+32] = hashlib.sha256(bytes(data[max(0,i-32):i])).digest()

          # Let it be garbage collected
          del data
          time.sleep(0.1)

      print("Memory pressure complete")
      PYTHON_EOF

        log_message "Memory pressure completed"
      }

      # ============================================================================
      # Network Activity Generation
      # ============================================================================
      generate_network_activity() {
        log_message "Generating network activity..."

        # Make HTTP requests to external endpoints
        for i in {1..3}; do
          # Try multiple endpoints, ignore failures
          timeout 10 curl -s "https://api.github.com/users/github" > /dev/null 2>&1 || true &
        done

        wait
        log_message "Network activity completed"
      }

      # ============================================================================
      # Disk I/O Generation
      # ============================================================================
      generate_disk_io() {
        log_message "Generating disk I/O..."

        local tmp_file="/tmp/idle_prevention_''${RANDOM}.tmp"

        # Write 100MB file
        dd if=/dev/urandom of="$tmp_file" bs=1M count=100 2>/dev/null

        # Read it back to ensure I/O
        cat "$tmp_file" > /dev/null

        # Clean up
        rm -f "$tmp_file"

        log_message "Disk I/O completed"
      }

      # ============================================================================
      # Main Execution
      # ============================================================================

      # Create log file if it doesn't exist
      touch "$LOG_FILE"

      # Rotate log if too large (keep under 10MB)
      if [ -f "$LOG_FILE" ]; then
        SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt $((10 * 1024 * 1024)) ]; then
          > "$LOG_FILE"
        fi
      fi

      log_message "========== IDLE PREVENTION CYCLE START =========="
      log_message "Current resources:"
      log_message "  CPU: $(top -bn1 | grep "Cpu(s)" || echo 'N/A')"
      log_message "  Memory: $(free -h | grep Mem || echo 'N/A')"
      log_message "  Disk: $(df -h / | tail -1 || echo 'N/A')"

      # Generate all types of load
      generate_cpu_load &
      CPU_PID=$!

      generate_memory_pressure &
      MEM_PID=$!

      generate_network_activity &
      NET_PID=$!

      generate_disk_io &
      DISK_PID=$!

      # Wait for all tasks to complete
      wait $CPU_PID || true
      wait $MEM_PID || true
      wait $NET_PID || true
      wait $DISK_PID || true

      log_message "========== IDLE PREVENTION CYCLE END =========="
      log_message ""

      exit 0
    '';
  };

  # Symlink script to /usr/local/bin for execution
  environment.systemPackages = with pkgs; [
    bash
    curl
    python3
    coreutils
  ];

  # Ensure idle prevention log directory exists
  systemd.tmpfiles.rules = [
    "d /var/log 0755 root root -"
  ];
}
