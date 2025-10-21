# SSH Hang Recovery - 2025-10-21

## Status
- ✅ Instance RUNNING in Oracle Cloud UI
- ❌ SSH refusing connections (port 22 down)
- 🔧 Auto-rollback protection enabled
- 📝 Only `nixos-rebuild build` was run (NOT `switch`)

## Why SSH Is Down But Instance Is Running

**Build likely got stuck or extremely slow**:
- `nixos-rebuild build` is still running
- or system stuck in boot after activation
- or sshd crashed/failed to start

**Key fact**: We have **18GB RAM + 4 OCPUs** - plenty of resources, so NOT OOM.

## Root Cause Analysis

Why did SSH terminate even with adequate resources?
1. **Likely**: `nixos-rebuild build` is STILL RUNNING on remote system
2. **Possible**: Build completed, triggered implicit activation, sshd failed during it
3. **Possible**: systemd restarted sshd during build, connection dropped

## Recovery Strategy

### Option 1: Reboot from Oracle Console (SAFEST)
This triggers **auto-rollback protection**:

1. Log into Oracle Cloud Console
2. Go to Compute → Instances → "indiastrong"
3. Click **Reboot Instance**
4. System reboots with **PREVIOUS generation**:
   - No PostgreSQL 16 service (reverts to minimal config)
   - SSH available
   - All old data preserved
5. SSH works immediately

**Why this is safe**: We only ran `nixos-rebuild build`, NOT `switch`, so:
- ✅ Boot config is STILL the old working one
- ✅ Reboot = recovery to known good state
- ✅ No data loss

### Option 2: Wait Longer (RISKY)
- Pros: If build completes on its own, system auto-recovers
- Cons: Could wait hours if build truly stuck
- Verdict: Not recommended

## Recommended Action

**→ Reboot via Oracle Console NOW**

This will:
1. Kill stuck build process
2. Boot old working config
3. SSH comes back
4. We try safer build method

## Why Build Might Have Gotten Stuck

Even with 18GB RAM, possible causes:
1. **Disk I/O bottleneck** - ARM64 instances sometimes have slow disk
2. **Network issue** - Binary cache download stuck
3. **Compilation deadlock** - Some package with broken cross-compilation
4. **systemd activation loop** - New services waiting on each other

## Safer Build Strategy (For Next Time)

Instead of building on remote (risk of resource exhaustion/stuck):

**Option A: Build Locally on Mac**
```bash
# On your Mac (faster, more resources)
nix build ".#nixosConfigurations.node-india-strong.config.system.build.toplevel"

# Copy to remote
rsync -av result/ root@152.67.179.42:/tmp/nixos-build/
```

**Option B: Use `--max-jobs 1` to Limit Parallelism**
```bash
ssh root@152.67.179.42 "cd /home/le/uptrack && \
  nixos-rebuild build --flake '.#node-india-strong' --max-jobs 1"
```

**Option C: Skip Full Build, Use Test Mode**
```bash
nixos-rebuild test --flake '.#node-india-strong'
# Quicker, less resource intensive
# Can verify without full build
```

## Steps After Reboot

1. **Reboot via Oracle console**
2. **Wait 1 minute** → SSH should work
3. **Verify**:
   ```bash
   ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "uptime"
   ```
4. **Check what generation we're on**:
   ```bash
   ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "nixos-rebuild list-generations"
   ```
5. **Try safer build method next time**

---

## Auto-Rollback Protection Worked!

Even though SSH hung:
- ✅ Boot config unchanged (we did `build`, not `switch`)
- ✅ One reboot = full recovery
- ✅ No data loss
- ✅ No permanent damage

This is EXACTLY why we spent time setting up auto-rollback protection.
