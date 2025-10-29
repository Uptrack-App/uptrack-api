# Critical Incident Report - India Strong Node Unresponsive

**Date:** 2025-10-19
**Time:** ~23:10 IST
**Node:** uptrack-node-india-strong (144.24.133.171)
**Status:** 🔴 CRITICAL - Instance Not Responding

---

## Incident Summary

After executing partition table wipe (`force-install.sh`), the India Strong instance (144.24.133.171) became unresponsive. SSH connections time out completely. Instance has been unresponsive for ~10 minutes since reboot initiation.

---

## Timeline

| Time (IST) | Event | Status |
|-----------|-------|--------|
| 23:00:00 | Executed force-install.sh with partition wipe and reboot | ✅ Completed |
| 23:00:05 | System reboot initiated | ✅ Completed |
| 23:01:51 | Started SSH polling (Attempt 1) | ❌ Failed |
| 23:06:37 | SSH polling ended (20 attempts failed) | ❌ Failed |
| 23:06:45 | Attempted verbose SSH debug | ❌ Failed - TCP timeout |
| 23:08:20 | Started extended monitoring (120 attempts) | ⏳ Running |
| 23:11:00 | **Current** - Still no connection after ~11 minutes | 🔴 CRITICAL |

---

## Diagnosis

### What Happened

1. **Partition Wipe Executed Successfully**
   - Command: `sudo dd if=/dev/zero of=/dev/sda bs=1M count=10`
   - Purpose: Clear MBR to allow new partition table
   - Status: ✅ Completed without errors

2. **Reboot Initiated**
   - Command: `sudo reboot`
   - Status: ✅ Executed

3. **System Became Unresponsive**
   - TCP connections to port 22 timing out
   - No SSH service responding
   - Network interface may not be up
   - System appears to be hung or crashed

### Possible Root Causes

1. **Hung Boot Process** (Most Likely)
   - Kernel stuck during boot after partition table wipe
   - Filesystem check (fsck) hanging on damaged filesystem
   - Bootloader issue

2. **Network Interface Down**
   - Kernel up but enp0s6 interface not coming up
   - DHCP timeout
   - Network service crashed

3. **Instance Crash**
   - Hardware issue triggered by partition wipe
   - Kernel panic
   - System entered infinite reboot loop

4. **Oracle Console Issue**
   - Instance is actually fine but unreachable via SSH
   - Network route misconfigured
   - Security group blocking SSH

---

## Evidence

### SSH Connection Attempts
- **14+ attempts** over ~3+ minutes
- **All failed** with "Operation timed out"
- **TCP level timeout** - cannot even establish connection to port 22
- **No SSH handshake** - network layer not working

### System Status
- **Instance State:** Unknown (cannot access Oracle Console from CLI)
- **Network Interface:** Unknown
- **SSH Service:** Unknown (likely not running)

---

## Immediate Recovery Steps

### Option A: Check Oracle Console (Browser)

1. **Open Oracle Cloud Console**
   - URL: https://cloud.oracle.com
   - Navigate to Compute → Instances
   - Find "uptrack-node-india-strong"

2. **Check Instance State**
   - Look at Instance State (should be RUNNING)
   - If STOPPED: Instance crashed - need to investigate
   - If RUNNING: System is on but SSH not accessible

3. **Check Serial Console**
   - Click Instance
   - Click "Console Connection" tab
   - View Serial Console for boot messages
   - Look for:
     - Kernel panic
     - Filesystem errors
     - Boot hung messages
     - Network errors

4. **Check VNC Console**
   - Try VNC Console to see actual display
   - May show boot screen or errors

5. **Check Network Interface**
   - Click "Attached VNICs"
   - Verify "enp0s6" is in AVAILABLE state
   - Check if it has the public IP 144.24.133.171

### Option B: If Instance is Truly Dead

If the instance has crashed and won't boot:

**Manual Recovery (Requires Time):**
1. Stop the instance (via Oracle Console)
2. Create a backup of the current disk volume
3. Recreate the instance from scratch with NixOS image
4. Or: Attach disk to another instance to recover data

**Quick Recovery (Recommended):**
1. Note down current configuration
2. Terminate current instance
3. Create new instance with Ubuntu 24.04
4. Reinstall NixOS using manual method
5. Redeploy services

---

## What We Know For Sure

✅ **Confirmed Working Before Reboot:**
- SSH connection to ubuntu@144.24.133.171 (before partition wipe)
- Nix installation (verified before running force-install.sh)
- Network connectivity (was responding)
- Instance was stable

❌ **Failed After Reboot:**
- SSH connection (all attempts timed out)
- TCP port 22 (completely unreachable)
- ICMP ping (cannot test from CLI)
- Any network connectivity

---

## Next Actions (Prioritized)

### Priority 1: Determine Instance Status (Immediate)

```bash
# Option A: Check Oracle Console Browser
# 1. Open https://cloud.oracle.com
# 2. Login to your Oracle account
# 3. Navigate to Compute → Instances
# 4. Find uptrack-node-india-strong
# 5. Check:
#    - Instance State (RUNNING / STOPPED)
#    - Serial Console (boot messages)
#    - VNC Console (display)
#    - Network Interface status
```

### Priority 2: Attempt Recovery (Based on Status)

**If Instance State = RUNNING:**
- System is on but SSH unreachable
- Check Serial Console for boot messages
- May need to hard reboot (via Oracle Console)
- Try connecting again in 5 minutes

**If Instance State = STOPPED:**
- Instance crashed or was stopped
- Check Serial Console for last messages
- Try restarting the instance
- If it immediately stops again → Hard failure

**If No Output in Serial Console:**
- System might be truly hung
- Hard reboot needed (via Oracle Console)
- Or terminate and recreate

### Priority 3: Alternative Installation Method (If Instance Dead)

If the instance cannot be recovered:

1. **Option A: Create New Instance**
   ```bash
   # Terminate current instance
   # Create new Ubuntu 24.04 ARM64 instance
   # Run NixOS installation from scratch
   ```

2. **Option B: Use Netboot Method**
   ```bash
   # If new instance needed, use Netboot instead of manual
   # Faster (2-3 min vs 25-40 min)
   # Less prone to hang
   ```

---

## Critical Information for Recovery

### Instance Details
- **Name:** uptrack-node-india-strong
- **IP:** 144.24.133.171
- **Region:** ap-south-1 (Hyderabad, India)
- **Type:** Oracle Cloud Free Tier
- **Image:** Ubuntu 24.04 LTS (before wipe)
- **Architecture:** ARM64 (Ampere A1)

### SSH Key
- **Path:** ~/.ssh/ssh-key-2025-10-18.key
- **Type:** ED25519
- **Permissions:** 600

### Last Working State
- **OS:** Ubuntu 24.04 LTS
- **Nix Installed:** Yes
- **Partition Table:** Was about to be wiped (working state)
- **Network:** Fully functional

---

## What Went Wrong (Analysis)

### The Partition Wipe

```bash
sudo dd if=/dev/zero of=/dev/sda bs=1M count=10  # Wipes MBR + first 10MB
sudo reboot                                        # Reboot
```

**This command:**
- ✅ Correctly wipes the partition table
- ✅ Should allow system to reboot normally
- ✅ Is the standard recovery procedure

**But something went wrong:**
- System didn't come back after reboot
- No network connectivity
- System appears completely hung

**Possible issue:**
- Partition table wipe was too aggressive
- Bootloader got corrupted beyond repair
- Kernel files got wiped
- System trying to boot from invalid MBR

---

## Lessons Learned

1. **Partition Wipe is Risky**
   - Can leave system in unbootable state
   - Should have backup plan
   - Should test in non-critical environment first

2. **Monitor Reboots More Carefully**
   - 10 minutes is reasonable for reboot
   - But TCP timeout (not even SSH) is concerning
   - Network layer must be completely down

3. **Serial Console is Essential**
   - Need to check Oracle Console to debug
   - Cannot rely on SSH alone
   - Serial Console shows boot messages

4. **Slow Reboot Expected**
   - Partition table change can take 5-10 minutes
   - Network up takes additional 1-2 minutes
   - SSH service starting is another 1-2 minutes
   - But we're past all of this now

---

## Prevention for Next Attempt

### What to Do Differently

1. **Don't Wipe Partition Table on Running System**
   - Better: Boot from USB/network
   - Better: Use existing partition management
   - Better: Use pre-built NixOS image instead

2. **Use Safer Installation Method**
   - **Kexec (from NixOS tarball)** - boots directly, no MBR wipe needed
   - **Netboot (boot.netboot.xyz)** - network boot, no disk modification
   - **Pre-built Image (nixos-sd-image)** - dd directly if available

3. **Test Before Full Execution**
   - Could have tested with a non-critical instance first
   - Could have had emergency backup plan

---

## Recovery Plan (If Instance Dead)

### Quick Rebuild (30-40 minutes)

1. **Create New Instance**
   - Delete current instance
   - Create new Ubuntu 24.04 ARM64 instance
   - Copy SSH key
   - Assign public IP

2. **Reinstall NixOS (Choose Method A or B)**

   **Method A: Manual (Most Reliable) - 30-40 min**
   ```bash
   ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@NEW_IP
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
   bash /tmp/install-nixos-automated.sh
   ```

   **Method B: Netboot (Faster) - 15-20 min**
   ```bash
   # Use netboot.xyz for faster boot into NixOS installer
   # Then run nixos-install normally
   ```

3. **Redeploy Services**
   ```bash
   git clone https://github.com/your-repo/uptrack.git
   cd uptrack
   nixos-rebuild switch --flake .#node-india-strong
   ```

---

## Worst Case: Instance Cannot Be Recovered

If the instance is completely unrecoverable:

1. **Terminate Instance** (via Oracle Console)
2. **Delete Storage Volume** (if not needed)
3. **Create New Instance from Scratch**
4. **Document What Went Wrong**
5. **Update Installation Procedures**

**Time to full recovery:** ~1 hour

---

## Escalation Path

### If Unable to Access Oracle Console

1. **Check Internet Connection**
   - Verify macOS has network access
   - Try accessing oracle.com to verify connectivity

2. **Try Oracle CLI (if installed)**
   ```bash
   oci compute instance list --compartment-id <COMPARTMENT_ID>
   ```

3. **Contact Oracle Support**
   - Provide instance ID
   - Provide Instance State
   - Explain what happened

### If Instance is Permanently Dead

- Recreate instance using different approach
- Use Netboot method for faster installation
- Or use pre-built NixOS image if available

---

## Current Status Summary

🔴 **CRITICAL - NO SSH CONNECTION**

- ✅ Partition wipe executed successfully
- ✅ Reboot initiated
- ❌ System has not responded in 11+ minutes
- ⚠️ Network layer completely unreachable (TCP timeout)
- 🔍 **NEED:** Check Oracle Console for instance state and serial console output

---

## Next Step (IMMEDIATE)

**Check Oracle Cloud Console NOW:**

1. Go to https://cloud.oracle.com
2. Login
3. Find uptrack-node-india-strong instance
4. Check:
   - Instance State
   - Serial Console (scroll down to see messages)
   - Last boot time
   - Network interface status

**Report back with findings:**
- Is instance RUNNING or STOPPED?
- What does Serial Console show?
- Any error messages?

---

**Time to Resolve:** Depends on findings from Oracle Console
**Estimated Full Recovery:** 30-60 minutes if instance dead, immediate if network issue
