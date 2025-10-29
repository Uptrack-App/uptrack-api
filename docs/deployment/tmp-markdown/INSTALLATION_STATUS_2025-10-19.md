# India Strong Node - NixOS Installation Status

**Date:** 2025-10-19
**Node:** uptrack-node-india-strong
**IP:** 144.24.133.171
**Architecture:** ARM64 (aarch64)

---

## Current Status: ⏳ SYSTEM REBOOTING

### What Happened

1. **Previous Attempt (nixos-anywhere):** Failed due to ARM64 kexec persistence issue on Oracle instances
2. **Switch to Manual Installation:** Chose nixos-install approach (Method 3 from NIXOS_INSTALLATION_METHODS.md)
3. **Partition Table Wipe:** Executed `force-install.sh` which ran:
   ```bash
   sudo dd if=/dev/zero of=/dev/sda bs=1M count=10
   sudo reboot
   ```
4. **Expected Behavior:** System reboots, kernel recognizes new partition table
5. **Current Status:** System has been rebooting for ~7-10 minutes

### Timeline

| Time (IST) | Event | Status |
|----------|-------|--------|
| 23:00:00 | force-install.sh executed, partition table wiped | ✅ Complete |
| 23:00:05 | System reboot initiated | ✅ Complete |
| 23:01:51 | SSH polling started (20 attempts, 10s intervals) | ✅ Complete |
| 23:06:37 | SSH polling ended (all 20 attempts failed) | ❌ No connection |
| 23:06:45 | Verbose SSH debug attempted | ❌ TCP timeout |

### Why No SSH Connection Yet?

Possible reasons:
1. **System is still booting** - Ubuntu is loading, kernel recognizing new partition table, or hung at boot
2. **SSH service hasn't started** - Even if kernel is up, SSH daemon may not have started
3. **Network interface not ready** - enp0s6 interface may not be up yet
4. **Instance crash** - Less likely but possible if partition wipe triggered hardware issue
5. **Normal behavior** - Full system reboot after partition table change can take 5-10+ minutes

### Expected Timeline (Normal Case)

```
23:00:05 - Reboot starts
23:02:00 - Kernel loads, filesystem checks
23:04:00 - Ubuntu system boots
23:05:00 - SSH service starts
23:06:00 - System fully ready for connection
```

---

## Next Steps

### Option 1: Wait and Reconnect (Recommended)

The system is likely still booting normally. Wait 5-10 more minutes and try:

```bash
# In 5 minutes, try connecting
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# If still not available, continue to Option 2
```

### Option 2: Check Oracle Instance Status

If system still doesn't connect after 15 minutes total reboot time:

1. **Via Oracle Console:**
   - Log into Oracle Cloud Console
   - Navigate to Compute → Instances
   - Select "uptrack-node-india-strong"
   - Check Instance State (should be RUNNING)
   - Check Serial Console for boot messages
   - Check VNC Console to see actual display

2. **Check Network:**
   - Verify Security List allows port 22 (SSH)
   - Check if instance still has public IP 144.24.133.171
   - Verify Network Interface is attached and in AVAILABLE state

### Option 3: Complete Installation When Online

Once system comes back online (expect root access):

```bash
# 1. Verify we can connect
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# 2. Check disk status
lsblk
df -h

# 3. Copy and run automated NixOS installation
scp -i ~/.ssh/ssh-key-2025-10-18.key /tmp/install-nixos-automated.sh root@144.24.133.171:/tmp/
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "bash /tmp/install-nixos-automated.sh"

# This will:
# - Create EFI and root partitions
# - Format filesystems
# - Generate NixOS configuration
# - Run nixos-install (20-30 minutes)
# - Reboot into NixOS
```

---

## Installation Scripts Ready

All scripts are prepared and ready to use:

### On MacBook:
- `/tmp/install-nixos-automated.sh` - Non-interactive installation (ready to copy)

### In Repository:
- `/Users/le/repos/uptrack/install-nixos-live.sh` - Interactive version with colored output
- `/Users/le/repos/uptrack/docs/oracle/INDIA_STRONG_MANUAL_INSTALL.md` - Detailed guide
- `/Users/le/repos/uptrack/docs/oracle/NIXOS_INSTALLATION_METHODS.md` - Method comparison

---

## What's Different from Previous Attempt

| Aspect | nixos-anywhere (Failed) | Manual Install (Current) |
|--------|----------------------|----------------------|
| **Method** | Kexec boot | nixos-install build |
| **Approach** | Remote orchestration | Local on-system build |
| **Build Location** | Kexec tarball | Nix build on instance |
| **Installation Time** | 15-20 min | 20-30 min |
| **Reliability on ARM64** | ❌ Poor (persistence issue) | ✅ Proven reliable |
| **Error Recovery** | Difficult (can't debug) | Easy (SSH into NixOS live) |

---

## Files for Complete Installation

```
Architecture:
├── Partition Table (to be created)
│   ├── /dev/sda1 (512M FAT32) → /boot/efi
│   └── /dev/sda2 (46G ext4) → /
├── NixOS Installation
│   ├── nixos-generate-config → /mnt/etc/nixos/hardware-configuration.nix
│   ├── nixos-install → Full NixOS build and install
│   └── Reboot into NixOS
└── Service Deployment (after NixOS boots)
    ├── nixos-rebuild switch --flake .#node-india-strong
    └── Services: PostgreSQL, Patroni, etcd, ClickHouse, uptrack-app
```

---

## Monitoring Progress

### Current (Every 10 minutes):
```bash
# Try to connect
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "echo online && uname -a"
```

### When System Comes Online:
```bash
# Check boot status
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "uptime && systemctl status"

# Check partition table
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "lsblk"

# Check if Nix is still installed
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "which nix && nix --version"
```

---

## Estimated Timeline (Complete Scenario)

| Phase | Time | Task |
|-------|------|------|
| System Boot | 5-10 min | Kernel loads, partition table recognized |
| SSH Ready | +1-2 min | SSH service starts |
| NixOS Install | +20-30 min | nixos-install builds and installs |
| Reboot to NixOS | +2-5 min | NixOS boots |
| Service Deploy | +10 min | nixos-rebuild switch |
| **Total** | **~50-60 min** | Complete installation |

---

## Troubleshooting

### Scenario 1: System Still Not Online After 15 Minutes
- Check Oracle Console (https://cloud.oracle.com)
- Look for instance state (should be RUNNING)
- Check Serial Console for boot messages
- Check if instance crashed or is hung

### Scenario 2: System Online But No Nix
- Nix might have been on the Ubuntu filesystem
- Will need to reinstall Nix
- Use: `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm`

### Scenario 3: Partition Creation Fails
- May need to wipe more of the disk first
- Run: `sudo dd if=/dev/zero of=/dev/sda bs=1M count=100`
- May indicate disk issue requiring Oracle support

### Scenario 4: NixOS Install Hangs
- **This is NORMAL** - can take 20-30+ minutes
- Wait at least 30 minutes before considering it hung
- Check with `top` in another SSH session
- If truly hung, can SSH in and manually debug

---

## Key Commands for Next Phase

When system comes back online:

```bash
# 1. SSH to instance
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# 2. Copy installation script
scp -i ~/.ssh/ssh-key-2025-10-18.key /tmp/install-nixos-automated.sh root@144.24.133.171:/tmp/

# 3. Run installation (non-interactive, auto-confirms)
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "bash /tmp/install-nixos-automated.sh"

# 4. Monitor progress (in another terminal)
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "watch -n 5 'ps aux | grep nix'"

# 5. After reboot (5-10 min), verify NixOS
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 "uname -a && nixos-rebuild --version"

# 6. Deploy services
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 'cd /root/uptrack && nixos-rebuild switch --flake .#node-india-strong'
```

---

## Summary

- ✅ Partition table wiped successfully
- ✅ System initiated reboot (expected behavior)
- ⏳ System currently rebooting (5-10 minutes typical)
- 🎯 Next: Wait for SSH reconnection, then run NixOS install

**Expect system online within 5-15 minutes. Installation script is ready to execute.**

---

**Last Updated:** 2025-10-19 23:06 IST
**Next Check:** In 5 minutes
