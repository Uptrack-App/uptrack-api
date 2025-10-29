# Idle Prevention System - Deployment Status
**Date**: 2025-10-21
**Status**: In Progress - Needs System Recovery
**Component**: Oracle Idle Prevention Service for India Strong

---

## What Was Done

### ✅ Completed
1. Created idle prevention service: `infra/nixos/services/idle-prevention.nix`
   - Generates CPU load via fibonacci computations
   - Creates memory pressure by allocating 200MB chunks
   - Makes network requests to external endpoints
   - Generates disk I/O via temp file writes
   - Runs every 5 minutes via systemd timer

2. Updated flake configuration to include idle prevention service
   - Modified `flake.nix` to import idle-prevention.nix for node-india-strong
   - Service configured to auto-start after PostgreSQL and network-online

### ⚠️ Pending
System may have experienced a boot issue during the latest deployment attempt.

---

## How It Works (Once Deployed)

### Idle Prevention Strategy

Oracle reclaims Always Free instances when:
- CPU utilization (95th percentile) < 20% for 7+ days
- Memory utilization < 20%
- Network utilization < 20%

**Solution**: Generate periodic load every 5 minutes to keep utilization > 20%

### Load Generation Cycle (Every 5 Minutes)

```
1. CPU Load (30-60 seconds)
   ├─ Parallel fibonacci computations
   ├─ Runs on 4 CPU cores simultaneously
   └─ Generates ~20-30% CPU utilization

2. Memory Pressure (10-20 seconds)
   ├─ Allocate 4 × 50MB chunks sequentially
   ├─ Process with SHA-256 hashing
   └─ Release for garbage collection

3. Network Activity (5-10 seconds)
   ├─ Make 3 HTTP requests to external APIs
   ├─ GitHub API endpoints
   └─ Each request 1-2KB data transfer

4. Disk I/O (10-20 seconds)
   ├─ Write 100MB random data to /tmp
   ├─ Read it back
   └─ Clean up temp file

Total cycle time: ~60 seconds
Frequency: Every 5 minutes
Log file: /var/log/idle-prevention.log
```

---

## System Status

**India Strong (152.67.179.42)**
- Previously: ✅ PostgreSQL 17.6 JIT running
- Current: ⚠️ SSH not responding (system may need recovery)

### Possible Issues

1. **Syntax error in idle-prevention.nix**
   - Bash script may have escaping issues
   - Python3 subprocess calls
   - File path issues

2. **systemd timer syntax error**
   - TimerConfig might have issues

3. **System still booting**
   - PostgreSQL initialization taking time
   - Could take 2-3 minutes

---

## Recovery Steps

### Step 1: Check System via Oracle Console
```
1. Log into Oracle Cloud Console
2. Go to Compute → Instances
3. Click "India Strong" instance
4. Look for console logs or restart button
5. If needed, click "Reboot Instance"
```

### Step 2: If System Won't Boot
Use auto-rollback to recover:
```
1. System shows boot menu (10 seconds)
2. Select "NixOS - Previous Generation"
3. System boots with Generation 12 (PostgreSQL running)
4. SSH access restored
```

### Step 3: Once SSH is Back Online
```bash
# Check current status
ssh root@152.67.179.42 "uptime && systemctl status postgresql"

# Check if idle-prevention is loaded
ssh root@152.67.179.42 "systemctl list-timers idle-prevention"

# If services failed, check journal
ssh root@152.67.179.42 "journalctl -u idle-prevention -n 50"
```

---

## Alternative Simpler Approach

If the bash script approach doesn't work, we can use a simpler NixOS approach:

```nix
# Simple idle prevention via cron
systemd.timers.idle-prevention = {
  timerConfig = {
    OnBootSec = "2min";
    OnUnitActiveSec = "5min";
    Unit = "idle-prevention.service";
  };
};

systemd.services.idle-prevention = {
  serviceConfig = {
    Type = "oneshot";
    ExecStart = ''
      ${pkgs.bash}/bin/bash -c '
        # Fibonacci in pure bash
        fibonacci() { ...}
        # Memory allocation
        dd if=/dev/urandom of=/tmp/test bs=1M count=100 && rm /tmp/test
        # Network
        curl https://api.github.com/users/github 2>/dev/null || true
      '
    '';
  };
};
```

---

## Permanent Solution

Once the system is stable, deploy the full Uptrack application which has native idle prevention:

**Files**:
- `/Users/le/repos/uptrack/lib/uptrack/health/idle_prevention.ex` - GenServer version
- `/Users/le/repos/uptrack/lib/uptrack/monitoring/idle_prevention_worker.ex` - Oban worker version

These run every 5 minutes/3 hours with proper Elixir error handling.

---

## Configuration Files

### Created
- ✅ `/Users/le/repos/uptrack/infra/nixos/services/idle-prevention.nix`
- ✅ Updated `/Users/le/repos/uptrack/flake.nix`

### Not Yet Deployed
- Idle prevention service needs debugging
- Alternative: Simpler bash-based approach
- Better: Full Uptrack app deployment

---

## Next Actions (For Next Session)

1. **Verify System Status**
   ```bash
   # Check if SSH is back
   ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "uptime"
   ```

2. **If system is down**
   - Use Oracle Console to reboot
   - Let auto-rollback recover to Generation 12
   - PostgreSQL will still be running

3. **If system is up but idle-prevention failed**
   - Check: `journalctl -u idle-prevention -n 50`
   - Could be: Bash script syntax, Python3 issue, or timer config
   - Fix and rebuild

4. **Test idle-prevention manually**
   ```bash
   # Once service is deployed
   systemctl start idle-prevention
   systemctl status idle-prevention
   tail -f /var/log/idle-prevention.log
   ```

5. **Monitor resource utilization**
   ```bash
   # Check CPU/Memory peaks
   top -b -n 1
   free -h
   ```

---

## Oracle's Reclamation Policy

**When instances get reclaimed:**
- 7-day measurement window
- CPU, Memory, Network ALL must be < 20%
- Rolling 95th percentile

**What prevents reclamation:**
- Any ONE metric > 20% during peak hours
- Idle prevention ensures peaks every 5 minutes

---

## Cost of Running Idle Prevention

**Per cycle (every 5 minutes)**:
- CPU: ~5-10 seconds @ 100% = ~2% average
- Memory: 200MB transient = ~1% of 18GB
- Network: ~5KB per request × 3 = 15KB = negligible
- Disk: 100MB write/read = <1% utilization

**Net effect**: Each cycle adds visible "spike" above 20% threshold

---

## Timeline

| Time | Event | Status |
|------|-------|--------|
| 11:30 UTC | PostgreSQL verified running | ✅ |
| ~15:50 UTC | Added idle-prevention service | 🔄 |
| ~15:55 UTC | Deployed flake with service | ⚠️ |
| 16:00+ UTC | System not responding to SSH | ⚠️ |

---

## Key Learnings

1. **systemd services need careful setup**
   - Must have proper `after` and `wantedBy`
   - Bash scripts need proper escaping
   - Python3 in systemd requires full paths

2. **Auto-rollback is essential**
   - If new config breaks boot, system recovers
   - Previous generation stays available
   - Gives safe way to test and iterate

3. **Simple > Complex**
   - Native bash scripts can be finicky
   - Elixir code (in Uptrack app) is cleaner
   - Eventually need to deploy full app

---

## Recommendations

### Short Term (This Session)
- [ ] Recover system via Oracle console reboot
- [ ] Verify PostgreSQL still running (Generation 12)
- [ ] Test simple idle prevention script manually

### Medium Term (Next Sessions)
- [ ] Deploy Uptrack application (has native idle prevention)
- [ ] Verify idle prevention Oban worker running
- [ ] Monitor Oracle Cloud metrics for utilization trends

### Long Term
- [ ] Setup monitoring dashboard for instance metrics
- [ ] Alert if utilization drops below 20% threshold
- [ ] Automate failover to second instance (India Weak)

---

**Status**: Phase 1 (PostgreSQL) ✅ | Phase 2 (Idle Prevention) 🔄 | Phase 3 (Full App) ⏳

