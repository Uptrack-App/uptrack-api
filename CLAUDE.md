
# NixOS Build & Deployment Guide

## Active Nodes

| Node | Provider | Location | Architecture | Specs |
|------|----------|----------|-------------|-------|
| nbg1 | Netcup | Nuremberg, DE | x86_64 | Coordinator Primary + Phoenix API |
| nbg2 | Netcup | Nuremberg, DE | x86_64 | Coordinator Standby + Phoenix API |
| nbg3 | Netcup | Nuremberg, DE | x86_64 | Citus Worker Primary |
| nbg4 | Netcup | Nuremberg, DE | x86_64 | Citus Worker Standby |
| india-rworker | Oracle Cloud | Hyderabad, IN | ARM64 | 1 OCPU, 6GB RAM - Backups & Logs |

### Legacy Nodes (Deprecated)
- hetzner-primary, contabo-secondary, contabo-tertiary

---

## Safe Deployment Workflow (Sequential Steps)

### Step 1: Validate config syntax (no network access needed)
```bash
nixos-rebuild dry-build --flake '.#<node-name>'
```
- Checks for Nix syntax errors
- No building, no system changes
- Quick validation (30 seconds)

### Step 2: Build everything without activation (no system changes)
```bash
nixos-rebuild build --flake '.#<node-name>' --max-jobs "$(nproc)"
```
- Compiles all packages and services
- Does NOT activate configuration
- Takes time but safe (can fail without affecting system)
- Result stored in /nix/store

### Step 3: Commit to boot (changes boot only, NOT current session)
```bash
nixos-rebuild switch --flake '.#<node-name>'
```
- Changes boot configuration
- Does NOT activate services immediately
- Current session completely unaffected
- SSH works perfectly
- User controls when to reboot

**Why `switch` instead of `test`**:
- `test` activates immediately - Can hang with PostgreSQL initdb
- `switch` only changes boot - Activation on reboot (expected)
- `switch` is production standard for NixOS
- Auto-rollback still protects you at boot time

### Step 4: Reboot to activate new configuration
```bash
sudo reboot
```
- System shuts down cleanly
- Boots with new configuration
- Services start normally during boot
- PostgreSQL initializes during systemd startup (expected, not blocking)

### Step 5: Verify After Reboot

After system comes back online:
```bash
# Check service status
systemctl is-active postgresql
systemctl status postgresql

# Verify database connection
psql -U postgres -c "SELECT version();"

# Check system logs for errors
journalctl -u postgresql -n 20 --no-pager
journalctl -u sshd -n 10 --no-pager

# Check resource usage
df -h /
free -h
```

## If Boot Fails (Auto-Rollback)

If new configuration fails to boot:
1. **Boot menu appears** (systemd-boot)
2. **Select "NixOS - Configuration X (previous)"**
3. **System boots with old working config**
4. **SSH works immediately**
5. **Investigate and fix config**
6. **Redeploy with corrected config**

## Why This Workflow Works

1. **Validation** (dry-build): Catches syntax errors before building
2. **Build** (build): Finds compilation issues before activation
3. **Switch** (switch): Changes boot config only, SSH always works
4. **Manual reboot**: User controls when activation happens
5. **Auto-rollback**: If boot fails, boot menu saves you

**Key difference from `test`**:
- `test` = immediate activation (risky with PostgreSQL initdb)
- `switch` + reboot = deferred activation (safe, controlled)

## Summary

| Phase | Command | What Happens | SSH Status | Risk |
|-------|---------|--------------|-----------|------|
| Validate | `dry-build` | Check syntax | OK | None |
| Build | `build` | Compile | OK | Low |
| Commit | `switch` | Boot config changes | OK | Low |
| Reboot | `reboot` | Manual | Restarting | Expected |
| Boot | (automatic) | Activate services | Restarting | Medium |
| Running | (normal) | Services active | OK | Low |

---

# AUTO-ROLLBACK PROTECTION (Prevent SSH Hang)

## Problem
If a service hangs during startup, SSH becomes unresponsive and system appears offline.

## Solution: Service Timeouts + Boot-time Health Check

### 1. Service Timeouts (Fail Fast, Don't Hang)
```nix
systemd.services.postgresql = {
  serviceConfig.TimeoutStartSec = "30s";  # Fail after 30 seconds
  serviceConfig.TimeoutStopSec = "10s";   # Force kill after 10s
  serviceConfig.Restart = "on-failure";   # Restart if fails
  serviceConfig.RestartSec = "5s";        # Wait 5s before retry
};
```

### 2. Don't Make SSH Depend on PostgreSQL
```nix
# WRONG - SSH will hang waiting for PostgreSQL
systemd.services.postgresql.wantedBy = [ "multi-user.target" ];

# RIGHT - PostgreSQL is optional, SSH is critical
systemd.services.postgresql.after = [ "network.target" ];
# (don't add to wantedBy, let it start independently)
```

### 3. Boot-Time Rollback Protection
Add to `/etc/nixos/configuration.nix`:
```nix
# Automatic rollback if boot fails
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;

# Set timeout so user can select previous generation
boot.loader.timeout = 10;  # Show boot menu for 10 seconds

# Add boot health check
boot.initrd.systemd.enable = true;
```

### 4. Systemd Emergency Timeout (Boot Fallback)
```nix
# Prevent boot from hanging indefinitely
systemd.extraConfig = ''
  DefaultTimeoutStartSec=30s
  DefaultTimeoutStopSec=10s
  DefaultTasksMax=8192
'';
```

## How It Works

1. **Service starts** - Sets 30-second timer
2. **Service hangs** - Timer expires after 30s
3. **Service marked failed** - Systemd stops waiting
4. **SSH becomes available** - Can SSH in and rollback
5. **User runs**: `nixos-rebuild switch --rollback` - Back to old config

## Manual Recovery (If Needed)

If system is completely unresponsive:
1. **Reboot** (power cycle)
2. **Boot Menu Appears** (systemd-boot)
3. **Select Previous Generation** (the one before broken deployment)
4. **System boots normally**
5. **SSH works**

---

# IMPLEMENTATION CHECKLIST

Before each `switch`, verify:

- [ ] Step 1: `nixos-rebuild dry-build` passed
- [ ] Step 2: `nixos-rebuild build` completed
- [ ] Step 3: `nixos-rebuild test` succeeded
- [ ] Service timeouts configured (30s for PostgreSQL)
- [ ] SSH doesn't depend on application services
- [ ] Health checks pass:
  - [ ] `systemctl is-active sshd` = active
  - [ ] `systemctl is-active postgresql` = active (or failed/inactive is OK)
  - [ ] SSH login works
  - [ ] Can run rollback command
- [ ] Then run: `nixos-rebuild switch`

## Why SSH Can Hang (Root Causes)

| Cause | Timeout Solution | Result |
|-------|------------------|--------|
| PostgreSQL fails to start | Add TimeoutStartSec=30s | Service fails cleanly, SSH available |
| Service waits on dead resource | Add timeout | Service marked failed after 30s |
| systemd waits forever | DefaultTimeoutStartSec | Boot menu appears to select old config |
| All services block each other | Fix dependencies | SSH starts independently |

## Worst Case: System Won't Boot at All

1. Power off
2. Power on - Boot menu appears
3. Select previous NixOS generation (before broken deployment)
4. Boot succeeds - SSH works again
5. Investigate and fix config
6. Redeploy safely
