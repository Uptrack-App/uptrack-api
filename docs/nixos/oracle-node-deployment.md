# Oracle Cloud NixOS Node Deployment Guide

## Critical Issue: Disko Module Incompatibility

### Problem

Oracle Cloud instances **cannot use the disko module** for disk partitioning. The disko configuration expects specific partition labels that don't exist on Oracle Cloud:

```nix
# ❌ BROKEN: Using disko on Oracle Cloud
modules = [
  disko.nixosModules.disko  # This expects ESP and swap partitions
  ./common.nix              # Imports disko.nix
  ./oracle-node-minimal.nix
];
```

**What happens:**
- System waits for `disk-main-ESP` partition (doesn't exist)
- System waits for `disk-main-swap` partition (doesn't exist)
- Deployment hangs indefinitely with `systemd` waiting for devices
- SSH becomes unresponsive

**System hangs at boot showing:**
```
JOB  UNIT                                          TYPE  STATE
6766 dev-disk-by\x2dpartlabel-disk\x2dmain\x2dswap.device  start running
5858 dev-disk-by\x2dpartlabel-disk\x2dmain\x2dESP.device   start running
```

### Root Cause

Oracle Cloud Free Tier instances only have **2 partitions**:
- `/dev/sda1` → `/boot` (vfat) = `disk-main-boot`
- `/dev/sda2` → `/` (ext4) = `disk-main-root`

Disko expects **4 partitions** (from `infra/nixos/disko.nix`):
- `disk-main-boot` - GRUB MBR (1MB)
- `disk-main-ESP` - EFI System Partition (512MB) ← **MISSING**
- `disk-main-swap` - Swap space (4GB) ← **MISSING**
- `disk-main-root` - Root filesystem (remaining)

### Solution

Create a separate common configuration **without disko** for Oracle nodes.

#### 1. Created `infra/nixos/common-oracle.nix`

```nix
# Common NixOS configuration for Oracle Cloud servers
{ config, pkgs, lib, ... }:
{
  # NO disko import - Oracle Cloud partitions already exist

  # Filesystem configuration for Oracle Cloud
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "ext4";
    options = [ "x-initrd.mount" "defaults" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-main-boot";
    fsType = "vfat";
    options = [ "defaults" ];
  };

  # Boot loader for Oracle Cloud (MBR GRUB, not EFI)
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";  # Oracle uses MBR GRUB
    efiSupport = false;   # No EFI on Oracle Free Tier
  };

  # ... rest of common configuration ...
}
```

#### 2. Updated `flake.nix`

```nix
india-rworker = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    # ✅ Use Oracle-specific common config (no disko)
    agenix.nixosModules.default
    ./infra/nixos/common-oracle.nix         # NOT common.nix!
    ./infra/nixos/oracle-node-minimal.nix
  ];
  specialArgs = { inherit self; };
};
```

### Verification Commands

Check current partition layout:
```bash
ls -la /dev/disk/by-partlabel/
# Should show:
# disk-main-boot -> ../../sda1
# disk-main-root -> ../../sda2
```

Check filesystem mounts:
```bash
mount | grep '^/dev'
# Should show:
# /dev/sda2 on / type ext4
# /dev/sda1 on /boot type vfat
```

Check fstab:
```bash
cat /etc/fstab
# Should show:
# /dev/disk/by-partlabel/disk-main-root / ext4 x-initrd.mount,defaults 0 1
# /dev/disk/by-partlabel/disk-main-boot /boot vfat defaults 0 2
```

### Deployment Workflow for Oracle Nodes

```bash
# 1. Sync flake to remote
rsync -av -e "ssh -i ~/.ssh/id_ed25519" \
  /Users/le/repos/uptrack/flake.nix \
  /Users/le/repos/uptrack/infra \
  root@REMOVED_IP:/root/uptrack/

# 2. Validate configuration
ssh -i ~/.ssh/id_ed25519 root@REMOVED_IP \
  "cd /root/uptrack && nixos-rebuild dry-build --flake '.#india-rworker'"

# 3. Build configuration (15-20 min first time, 5-10 min subsequent)
ssh -i ~/.ssh/id_ed25519 root@REMOVED_IP \
  "cd /root/uptrack && nixos-rebuild build --flake '.#india-rworker' --max-jobs 3"

# 4. Deploy (commit to boot config only, SSH always works)
ssh -i ~/.ssh/id_ed25519 root@REMOVED_IP \
  "cd /root/uptrack && nixos-rebuild switch --flake '.#india-rworker'"

# 5. Reboot to activate new configuration
ssh -i ~/.ssh/id_ed25519 root@REMOVED_IP "sudo reboot"
```

### Boot Loader Configuration

Oracle Cloud uses **MBR GRUB**, not EFI:
- Boot loader: GRUB installed on `/dev/sda` MBR
- Boot menu timeout: 10 seconds (allows rollback to previous generation)
- No EFI partition needed

Compare to Hetzner/Contabo (uses EFI):
```nix
# Hetzner/Contabo (with disko)
boot.loader.grub = {
  enable = true;
  efiSupport = true;         # EFI boot
  efiInstallAsRemovable = true;
};

# Oracle Cloud (without disko)
boot.loader.grub = {
  enable = true;
  device = "/dev/sda";       # MBR boot
  efiSupport = false;        # No EFI
};
```

## Oracle Cloud Specific Configuration

### oracle-node-minimal.nix

Includes:
- PostgreSQL 17 with JIT compilation
- Idle prevention (runs every 5 minutes, starts 20 min after boot)
- Firewall: ports 22, 80, 443, 4000, 5432
- Minimal packages: curl, git, vim, wget, htop, tmux, bc

**Why "minimal"?**
- No ClickHouse (too resource-intensive for Oracle Free Tier)
- No Uptrack app service module (deployed as release instead)
- Lightweight idle prevention (reduced CPU/memory load)

### Idle Prevention Configuration

```nix
# Systemd timer - run every 5 minutes
systemd.timers.idle-prevention = {
  timerConfig = {
    OnBootSec = "20min";       # Start 20 minutes after boot
    OnUnitActiveSec = "5min";  # Then every 5 minutes
    Persistent = true;
  };
};
```

**Why 20 minutes delay?**
- Allows PostgreSQL initialization to complete
- Prevents resource contention during boot
- Safe for SSH availability

## Files Created/Modified

1. **Created:**
   - `infra/nixos/common-oracle.nix` - Oracle-specific common config without disko

2. **Modified:**
   - `flake.nix` - Updated `india-rworker` to use `common-oracle.nix`

## Common Errors

### Error: `The option 'disko' does not exist`

**Cause:** Configuration imports `common.nix` which includes `disko.nix`, but disko module not loaded in flake.

**Solution:** Use `common-oracle.nix` instead of `common.nix`.

### Error: `Failed assertions: - The 'fileSystems' option does not specify your root file system`

**Cause:** No `fileSystems` configuration when disko is removed.

**Solution:** Add explicit `fileSystems` configuration in `common-oracle.nix`.

### System hangs at deployment with "waiting for devices"

**Cause:** Systemd waiting for `disk-main-ESP` or `disk-main-swap` partitions that don't exist.

**Solution:** Remove disko module, use `common-oracle.nix`.

### SSH connection refused after deployment

**Cause:** System hung waiting for non-existent partitions, or rebooted into old generation.

**Solution:**
1. Reboot via Oracle Cloud console
2. System will boot into safe generation (auto-rollback)
3. Re-deploy with fixed configuration

## Rollback Procedure

If deployment breaks SSH:
1. Access Oracle Cloud console → Instance → Reboot
2. System boots to previous working generation
3. SSH should be available
4. Check what went wrong:
   ```bash
   nixos-rebuild list-generations
   readlink -f /run/current-system
   ```
5. Fix configuration and redeploy

## Summary

**Oracle Cloud nodes require:**
- ✅ `common-oracle.nix` (NOT `common.nix`)
- ✅ Explicit `fileSystems` configuration
- ✅ MBR GRUB (NOT EFI)
- ✅ No disko module
- ✅ Manual partition labels: `disk-main-root`, `disk-main-boot`

**Do NOT use:**
- ❌ `common.nix` (imports disko)
- ❌ `disko.nixosModules.disko`
- ❌ EFI boot configuration
- ❌ Swap partition (not available)
