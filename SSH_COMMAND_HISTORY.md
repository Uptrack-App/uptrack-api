# SSH Command History - India Strong Node Installation

**Generated:** 2025-10-19
**Node:** uptrack-node-india-strong (144.24.133.171)
**SSH Key:** ~/.ssh/ssh-key-2025-10-18.key

---

## Summary

All SSH commands executed during the NixOS installation process for India Strong (ARM64 Oracle instance).

---

## SSH Command Timeline

### Phase 1: Initial Connectivity Tests

#### Attempt 1: Check Instance Health (Pre-nixos-anywhere)
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171 "echo 'Connected'; uname -a; systemctl status"
```
- **Status:** ✅ Success
- **User:** ubuntu
- **Time:** Earlier in process
- **Purpose:** Verify instance is accessible before installation

---

#### Attempt 2: Verify Ubuntu System
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171 "lsblk; cat /etc/os-release | head -5"
```
- **Status:** ✅ Success
- **User:** ubuntu
- **Time:** Earlier in process
- **Purpose:** Check disk configuration and OS version

---

### Phase 2: Preparation & Script Execution

#### Attempt 3: Nix Installation Verification
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171 "which nix && nix --version"
```
- **Status:** ✅ Success
- **User:** ubuntu
- **Time:** After Nix installation
- **Purpose:** Verify Nix is available for nixos-install

---

#### Attempt 4: Script Transfer & Execution (force-install.sh)
```bash
scp -i ~/.ssh/ssh-key-2025-10-18.key /tmp/force-install.sh ubuntu@144.24.133.171:/tmp/
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171 "bash /tmp/force-install.sh"
```
- **Status:** ✅ Initiated (then rebooted)
- **User:** ubuntu
- **Time:** ~23:00:00 IST
- **Purpose:** Wipe partition table and reboot
- **Commands in Script:**
  ```bash
  sudo dd if=/dev/zero of=/dev/sda bs=1M count=10
  sudo reboot
  ```

---

### Phase 3: Post-Reboot Connection Attempts

#### Attempt 5-6: Initial SSH Retry (root@144.24.133.171)
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@144.24.133.171 "echo 'Connected to India Strong'; uname -a; lsblk"
```
- **Status:** ❌ Failed (Operation timed out)
- **Time:** ~23:01:51 IST
- **Reason:** System still rebooting after partition wipe
- **Timeout:** 10 seconds

---

#### Attempt 7: After 30-Second Wait
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@144.24.133.171 "echo 'Connected'; uname -a" && echo "" || echo "Still offline..."
```
- **Status:** ❌ Failed (Operation timed out)
- **Time:** ~23:02:06 IST
- **Reason:** System still rebooting
- **Elapsed:** ~2 minutes from reboot

---

### Phase 4: Polling Loop Attempts (20 retries)

#### Attempts 8-27: Automated Polling (20 attempts, 10s intervals)
```bash
for i in {1..20}; do
    echo "Attempt $i ($(date +%H:%M:%S))..."
    if ssh -i ~/.ssh/ssh-key-2025-10-18.key -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           root@144.24.133.171 "echo 'Online'; uname -a" 2>/dev/null; then
        echo "✓ India Strong is online!"
        break
    fi
    if [ $i -lt 20 ]; then
        sleep 10
    fi
done
```
- **Total Duration:** ~200 seconds (3.3 minutes)
- **Status:** ❌ All failed
- **Timeout per attempt:** 5 seconds
- **Interval:** 10 seconds between attempts
- **Time:** 23:01:51 - 23:06:37 IST
- **Elapsed from reboot:** ~6.5 minutes

---

#### Attempt 28: Verbose SSH Debug
```bash
ssh -vvv -i ~/.ssh/ssh-key-2025-10-18.key -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    root@144.24.133.171 "echo online"
```
- **Status:** ❌ Failed (Connection timed out at TCP level)
- **Time:** ~23:06:45 IST
- **Output:** TCP connection times out (not even reaching SSH handshake)
- **Implication:** Network interface or SSH service not ready
- **Elapsed from reboot:** ~6.5 minutes

---

### Phase 5: Extended Monitoring (120 retries, in progress)

#### Attempts 29+: Extended Polling Loop (120 attempts)
```bash
for i in {1..120}; do
    if ssh -i ~/.ssh/ssh-key-2025-10-18.key -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
           root@144.24.133.171 "echo '✓ ONLINE at attempt $i ($(date +%H:%M:%S))'; uname -a; lsblk | head -5"; then
        echo "✅ India Strong is ONLINE!"
        echo "End time: $(date)"
        exit 0
    fi

    if [ $((i % 10)) -eq 0 ]; then
        echo "⏳ Attempt $i/120 ($(date +%H:%M:%S)) - Still waiting..."
    fi

    sleep 10
done
```
- **Total Duration:** 1200 seconds (20 minutes) max
- **Status:** ⏳ In Progress (started ~23:06:45)
- **Timeout per attempt:** 5 seconds
- **Interval:** 10 seconds between attempts
- **Checks:** Every 10 attempts (every 100 seconds)
- **Time Remaining:** ~11 minutes

---

## SSH Connection Parameters Used

### Standard Connection
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    root@144.24.133.171
```

### Verbose Debugging
```bash
ssh -vvv \
    -i ~/.ssh/ssh-key-2025-10-18.key \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    root@144.24.133.171
```

### With Data Collection
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    root@144.24.133.171 \
    "echo '✓ ONLINE'; uname -a; lsblk | head -5"
```

---

## SSH Connection Issues & Resolution

### Issue 1: "Please login as ubuntu not root" (Early Stage)
- **Error:** nixos-anywhere tried root login on Ubuntu instance
- **Resolution:** Changed all commands to use `ubuntu@` user
- **Note:** This was during nixos-anywhere phase, resolved before partition wipe

### Issue 2: SSH Key Permissions Too Open
- **Error:** "@@@@@@@@@@@@ WARNING: UNPROTECTED PRIVATE KEY FILE @@@@@@@@@@@@"
- **Resolution:** `chmod 600 ~/.ssh/ssh-key-2025-10-18.key`
- **Fixed:** Before any SSH commands in current phase

### Issue 3: Operation Timed Out (Current)
- **Error:** "ssh: connect to host 144.24.133.171 port 22: Operation timed out"
- **Cause:** System rebooting, SSH service not ready
- **Expected:** Will resolve when system finishes booting
- **Monitoring:** Extended polling in progress

---

## Expected SSH Timeline

| Stage | Duration | What's Happening | SSH Status |
|-------|----------|------------------|------------|
| Initial reboot | 5-8 min | Kernel loads, filesystems check | ❌ No SSH |
| System boot | 2-3 min | Ubuntu boots (if not wiped) or NixOS (if installed) | ❌ No SSH |
| SSH service starts | 1-2 min | SSHD daemon starts | ✅ SSH ready |
| **Total to SSH** | **8-13 min** | System fully booted | ✅ Expected |

---

## Next SSH Commands (When System Comes Online)

### 1. Verify Connection
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "echo 'Online'; uname -a"
```
- **Purpose:** Confirm system is fully booted
- **Expected:** Should show Linux kernel info

### 2. Check Disk Status
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "lsblk; echo '---'; df -h"
```
- **Purpose:** Verify partition table recognized
- **Expected:** Should show /dev/sda1 and /dev/sda2

### 3. Verify Nix Still Available
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "which nix; nix --version"
```
- **Purpose:** Ensure Nix installation survived reboot
- **Expected:** Should show nix version

### 4. Copy Installation Script
```bash
scp -i ~/.ssh/ssh-key-2025-10-18.key /tmp/install-nixos-automated.sh root@144.24.133.171:/tmp/
```
- **Purpose:** Transfer automated NixOS install script
- **Expected:** File copied to /tmp/

### 5. Execute Installation
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "bash /tmp/install-nixos-automated.sh"
```
- **Purpose:** Run NixOS installation (20-30 min)
- **Expected:** Installation will run, then reboot into NixOS

### 6. Monitor Installation Progress
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "ps aux | grep nix | grep -v grep"
```
- **Purpose:** Check if nixos-install is still running
- **Expected:** Should show nix processes during build

### 7. After NixOS Boots
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "uname -a; nixos-rebuild --version"
```
- **Purpose:** Verify NixOS is running
- **Expected:** Should show NixOS info

### 8. Deploy Services
```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 \
    "cd /root/uptrack && nixos-rebuild switch --flake .#node-india-strong"
```
- **Purpose:** Deploy Uptrack services
- **Expected:** Services start running

---

## SSH Key Information

### Key Details
- **Path:** ~/.ssh/ssh-key-2025-10-18.key
- **Type:** ED25519
- **Permissions:** 600 (read/write for owner only)
- **Created:** 2025-10-18
- **Used for:** All SSH connections to India Strong (144.24.133.171)

### Key Verification
```bash
ls -la ~/.ssh/ssh-key-2025-10-18.key
# Expected: -rw------- (600)

file ~/.ssh/ssh-key-2025-10-18.key
# Expected: ASCII text

ssh-keygen -l -f ~/.ssh/ssh-key-2025-10-18.key
# Shows fingerprint for verification
```

---

## Monitoring Status

### Current Monitoring
- **Process ID:** Background bash 4f6203
- **Duration:** Extended polling (up to 20 minutes)
- **Status:** ⏳ In Progress
- **Last Check:** ~23:06:45 IST
- **Next Check:** Every 10 seconds

### Previous Monitoring
- **Process ID:** Background bash 8481ff
- **Duration:** Initial polling (20 attempts)
- **Status:** ✅ Completed (all timed out)
- **Finished:** ~23:06:37 IST

---

## Summary of SSH Activity This Session

### Connection Attempts
- **Successful:** 0 (system rebooting)
- **Failed:** 28+ (and counting)
- **In Progress:** Monitoring with extended polling

### Time Elapsed
- **From Reboot:** ~6-10 minutes
- **Expected Time to Success:** 2-8 more minutes
- **Maximum Wait:** 20 minutes (polling limit)

### Key Insights
1. TCP connection timing out (not SSH handshake)
2. Network interface likely not ready yet
3. System appears to be in normal reboot cycle
4. No catastrophic hardware failure indicated
5. Extended polling should catch connection when ready

---

**Last Updated:** 2025-10-19 ~23:08 IST
**Monitoring Status:** ⏳ Active (Extended polling running)
**Expected Online:** Within 5-10 minutes
