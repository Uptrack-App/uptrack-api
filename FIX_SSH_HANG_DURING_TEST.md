# Preventing SSH Hang During `nixos-rebuild test`

## Problem

During `nixos-rebuild test`, the system hangs and SSH refuses connections for 5+ minutes.

**Root Cause**: PostgreSQL service auto-starts during activation:
```
1. nixos-rebuild test runs
2. systemd activates new config
3. Tries to start PostgreSQL service (includes initdb initialization)
4. initdb takes minutes to initialize database
5. systemd is blocked waiting for PostgreSQL to start
6. sshd can't restart, becomes unresponsive
7. SSH hangs
```

## Solution 1: Skip `test`, Use `switch` Directly (RECOMMENDED)

**The Issue with `test`:**
- Activates services immediately in current session
- PostgreSQL initialization blocks everything
- SSH gets stuck

**Why `switch` is Better:**
- Only changes boot configuration
- Activation happens on next reboot (not now)
- Current session unaffected
- If activation fails on boot, auto-rollback recovers

**Workflow:**
```bash
# Step 1: dry-build (validate)
nixos-rebuild dry-build --flake '.#node-india-strong'

# Step 2: build (compile)
nixos-rebuild build --flake '.#node-india-strong' --max-jobs 3

# Step 3: SKIP test, go straight to switch
nixos-rebuild switch --flake '.#node-india-strong'

# Step 4: Reboot to activate
reboot

# Step 5: Auto-rollback protection kicks in if needed
# Boot menu appears → Select previous generation if broken
```

**Why this is safe:**
- ✅ Auto-rollback protection enabled
- ✅ If activation fails, just select old generation
- ✅ SSH works immediately after reboot
- ✅ Much faster deployment

## Solution 2: Make PostgreSQL Optional (No Auto-Start)

Don't include PostgreSQL in `wantedBy`:

```nix
# BEFORE (causes hang):
systemd.services.postgresql.wantedBy = [ "multi-user.target" ];

# AFTER (optional, manual start):
# Don't add to wantedBy
# Just ensure it's available when needed

systemd.services.postgresql = {
  enable = true;
  after = [ "network.target" ];
  # No wantedBy - doesn't auto-start
  serviceConfig = {
    TimeoutStartSec = "60s";
  };
};
```

**Problem**: Application needs PostgreSQL on boot, so this doesn't work.

## Solution 3: Pre-Initialize Database

Initialize PostgreSQL before deployment so activation is fast:

```bash
# On remote, before rebuilding
ssh root@152.67.179.42 "initdb /var/lib/postgresql/16/main" 2>/dev/null || true

# Then deployment is fast (no initdb during activation)
```

## Solution 4: Simplify - Don't Use NixOS Service

Deploy PostgreSQL without NixOS managing the service:

```nix
# Instead of services.postgresql:
environment.systemPackages = [ pkgs.postgresql_16 ];

# Manually manage with systemd user service or script
```

**Problem**: More complex, needs manual management.

## RECOMMENDED: Use `switch` Directly

**Why**:
1. ✅ Simplest (no code changes needed)
2. ✅ Fastest (activation happens at boot, not now)
3. ✅ Safest (auto-rollback on failure)
4. ✅ Clearest workflow (what you're changing and when)

**New Deployment Workflow:**

```bash
# On remote system (indiastrong)

# Step 1: Validate config
nixos-rebuild dry-build --flake '.#node-india-strong'
# Takes: 30 seconds

# Step 2: Build (compile everything)
nixos-rebuild build --flake '.#node-india-strong' --max-jobs 3
# Takes: 15-20 minutes (first time), 5-10 min (subsequent)

# Step 3: Commit to boot (NO test)
nixos-rebuild switch --flake '.#node-india-strong'
# Takes: <1 minute
# RESULT: Config changed for next boot

# Step 4: Reboot to activate
sudo reboot
# System comes back with new config
# Auto-rollback available if needed

# Step 5: Verify
ssh root@152.67.179.42 "systemctl status postgresql"
```

## Why This Works

| Step | What Happens | SSH Status |
|------|--------------|-----------|
| `switch` | Changes boot config only | ✅ Works (no activation) |
| `reboot` | System shuts down cleanly | ✅ Expected (reboot) |
| Boot | Loads new config from disk | 🔄 Booting |
| systemd startup | PostgreSQL initializes at boot | 🔄 Services starting |
| Multi-user target | All services ready | ✅ SSH works |
| Auto-rollback menu | If boot fails, pick old generation | ✅ Recovery ready |

## Comparison: `test` vs `switch`

| Aspect | `test` | `switch` |
|--------|--------|---------|
| Activation timing | NOW (immediate) | NEXT BOOT |
| Current session | Affected | Unaffected |
| SSH during activation | ❌ Can hang | ✅ Works |
| Boot config changes | No | Yes |
| Rollback | Reboot | Boot menu |
| Time to see result | Minutes | Seconds (after reboot) |
| Risk | Higher (immediate) | Lower (deferred) |

## Recommendation

**Use `switch` directly, skip `test`.**

This is actually the **intended NixOS workflow** for production deployments:
- `test` is for development/experimentation
- `switch` is for production deployments
- Let the system activate on boot, not immediately

## If Activation Fails After Reboot

1. **Reboot hangs** → System won't boot to new config
2. **Auto-rollback menu appears** (systemd-boot)
3. **Select "NixOS - Previous Generation"**
4. **System boots with old working config**
5. **Investigate and fix config**
6. **Redeploy with `switch`**

This is **exactly what auto-rollback protection is for**.
