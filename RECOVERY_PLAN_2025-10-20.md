# Recovery Plan - NixOS Rebuild Failure & Idle Prevention Deployment

**Date**: 2025-10-20
**System**: indiastrong (152.67.179.42)
**Issue**: NixOS rebuild failed, system went into emergency mode, then recovered
**Status**: System is back online, code is deployed, now recovering

---

## What Happened

### Phase 1: Initial Deployment ✅
- Idle prevention code synced to ~/uptrack
- Git repository initialized
- All files committed (a6d7635)

### Phase 2: NixOS Rebuild ⚠️
- Command: `sudo nixos-rebuild switch --flake '.#node-india-strong'`
- System began compilation
- System rebooted to activate changes
- **Result**: Boot failed, entered emergency mode

### Phase 3: System Recovery ✅
- System rolled back to previous working state
- SSH came back online
- All deployed code still in place at ~/uptrack

---

## Current Status

### ✅ What's Working
- SSH access restored
- Git repository intact at ~/uptrack
- Idle prevention code still deployed
- Code committed: a6d7635

### ❌ What Needs to be Fixed
- Uptrack service not running
- /opt/uptrack directory doesn't exist
- No compiled release available

---

## Why the NixOS Rebuild Failed

**Root Cause**: The flake configuration tried to rebuild the entire NixOS system with Uptrack service, but likely:

1. Service configuration had a syntax error or conflict
2. Missing dependency for aarch64 architecture
3. Service tried to bind to already-used port
4. Permission issue during system activation

**Better Approach**: Don't try a full system rebuild again. Instead:

1. **Just compile the code** (already done or in progress)
2. **Create a simple release** with `mix release`
3. **Deploy to /opt/uptrack** manually
4. **Start service** using existing systemd configuration

This is **safer** because:
- We avoid another system-level rebuild that might fail again
- We can test code locally first
- We have more control over the deployment
- Easier to debug if something goes wrong

---

## Recovery Steps (In Progress)

### Step 1: Compile the Code ⏳ IN PROGRESS
```bash
cd ~/uptrack
MIX_ENV=prod nix-shell --run 'mix compile'
```
**Status**: Running in background, should complete in 2-5 minutes

### Step 2: Build Release (Next)
Once compilation succeeds:
```bash
MIX_ENV=prod nix-shell --run 'mix release --overwrite'
```
This creates `/home/le/uptrack/_build/prod/rel/uptrack/`

### Step 3: Deploy Release
```bash
sudo mkdir -p /opt/uptrack
sudo cp -r _build/prod/rel/uptrack/* /opt/uptrack/
sudo chown -R uptrack:uptrack /opt/uptrack/
sudo systemctl daemon-reload
sudo systemctl start uptrack
```

### Step 4: Verify
```bash
sudo systemctl status uptrack
curl http://localhost:4000/api/health | jq '.checks.idle_prevention'
tail -50 /var/log/uptrack/*.log | grep IdlePrevention
```

---

## Why This Approach is Better

| Aspect | NixOS Rebuild | Simple Release Deploy |
|--------|---------------|----------------------|
| **Complexity** | Very High | Low |
| **Points of Failure** | Many | Few |
| **Debug Difficulty** | Hard | Easy |
| **Rollback Time** | 15+ min | < 1 min |
| **Risk** | HIGH | LOW |
| **Code Testing** | No | Yes |

---

## Next Actions

### Immediate (Now)

1. **Wait for compilation** to complete (~2-5 minutes)
2. **Check for errors**: `BashOutput` to monitor compilation
3. **If successful**: Proceed to build release
4. **If errors**: Fix code issues and recompile

### Short-term (Within 15 minutes)

1. Build release with `mix release`
2. Deploy to `/opt/uptrack`
3. Start uptrack service
4. Verify idle prevention running

### Once Verified on indiastrong

1. Document final working setup
2. Deploy to india-week using **same approach** (not NixOS rebuild)
3. Verify both instances running

---

## Lessons Learned

### What Worked Well
✅ Code deployment to instance
✅ Git repository setup
✅ System recovery automatic
✅ SSH access restored quickly

### What We Should Change
❌ Don't attempt full NixOS system rebuilds during deployment
❌ Build and test code locally first
❌ Use simpler deployment methods (releases, systemd services)

### For Future Deployments

1. **Compile first**: `mix compile --verbose`
2. **Test locally**: `mix test` on local machine
3. **Build release**: `mix release --overwrite`
4. **Simple deploy**: Copy release to /opt
5. **Use systemd**: Not NixOS modules

---

## Success Criteria

- ✅ Code compiles without errors
- ✅ Release builds successfully
- ✅ Uptrack service starts
- ✅ Idle prevention logs appear every 5 minutes
- ✅ Health endpoint shows idle stats
- ✅ Oban job executes every 3 hours

---

## Backup Plan (If Compilation Fails)

If compilation fails, we have options:

**Option A**: Debug compilation errors
```bash
cd ~/uptrack
MIX_ENV=prod nix-shell --run 'mix compile --verbose'
```

**Option B**: Check git log to see what changed
```bash
cd ~/uptrack
git diff HEAD~1 HEAD lib/uptrack/health/
```

**Option C**: Revert to previous commit (if needed)
```bash
cd ~/uptrack
git revert HEAD --no-edit
MIX_ENV=prod nix-shell --run 'mix compile'
```

---

## Important Notes

1. **The idle prevention code is already on the system** - we just need to compile it
2. **System is stable** - rolled back to previous working state
3. **No risk of data loss** - code is versioned in git
4. **Safer approach** - avoid system-level rebuilds, use application releases

---

## Monitoring Compilation

Check progress:
```bash
# From local machine
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 "ps aux | grep mix"

# View recent logs
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 "tail -20 /tmp/compile.log"
```

Expected time: 2-5 minutes for first compile

---

**Status**: Recovery in progress - waiting for compilation to complete
**Next Update**: When compilation finishes
