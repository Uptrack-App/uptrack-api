# NixOS Installation Methods on Oracle Cloud

## Overview

Oracle Cloud does not provide NixOS as a pre-built image option. Instead, users must install it manually on a base Linux distribution (usually Ubuntu or Oracle Linux). There are several proven methods used by the community.

---

## Method 1: Kexec (Most Common, Recommended)

### Why Kexec?
- **Efficient**: Uses a compressed kexec tarball (~300MB vs 2GB disk image)
- **No reboots needed**: Boots NixOS installer from existing OS
- **Works well**: Proven on Oracle's free tier ARM64 (Ampere A1)
- **Most documented**: Many tutorials and community support

### Steps

1. **Boot into existing Linux (Ubuntu)**
   ```bash
   ssh ubuntu@<instance-ip>
   ```

2. **Download NixOS kexec tarball**
   ```bash
   cd /tmp
   curl -L https://hydra.nixos.org/build/<build-id>/download/1/nixos-kexec-<arch>.tar.zst \
     -o nixos-kexec.tar.zst
   ```

3. **Extract and prepare**
   ```bash
   tar -xf nixos-kexec.tar.zst
   cd kexec
   ```

4. **Run kexec to boot NixOS installer**
   ```bash
   sudo ./kexec/run
   ```
   - Wait 5-10 minutes (may appear stuck)
   - Wait for line: `+ kexec -e`
   - System will reboot into NixOS live

5. **In NixOS live environment**
   ```bash
   ssh root@<instance-ip>
   nixos-generate-config --root /mnt
   nixos-install --root /mnt
   reboot
   ```

### Pros
- ✅ Works on ARM64
- ✅ Well documented
- ✅ Efficient use of bandwidth
- ✅ No disk image upload needed

### Cons
- ❌ Complex kexec setup
- ❌ Requires compiling/downloading specific builds
- ❌ Takes time to boot into NixOS

---

## Method 2: Netboot (Newer, Simpler)

### Why Netboot?
- **Simpler**: Uses netboot.xyz infrastructure
- **No custom builds**: Uses standard netboot environment
- **Works over network**: No need to download/extract

### Steps

1. **Download netboot.xyz EFI**
   ```bash
   curl -L https://boot.netboot.xyz/ipxe/netboot.xyz-arm64.efi \
     -o /tmp/netboot.xyz.efi
   ```

2. **Copy to EFI partition**
   ```bash
   sudo mount /dev/sda15 /mnt
   sudo cp /tmp/netboot.xyz.efi /mnt/
   ```

3. **Reboot and select from EFI**
   ```bash
   sudo reboot
   # Press Escape repeatedly during boot
   # Select netboot.xyz from EFI menu
   # Select NixOS from netboot.xyz menu
   ```

4. **Install NixOS**
   - System boots into NixOS live
   - Follow standard installation

### Pros
- ✅ Simpler setup
- ✅ No custom builds needed
- ✅ Uses standard netboot infrastructure

### Cons
- ❌ Requires EFI boot menu access
- ❌ May not work if EFI is locked down
- ❌ Network boot can be slower

---

## Method 3: Manual Disk Partition + nixos-install (What We're Using)

### Why This Method?
- **Works from existing OS**: No kexec complexity
- **Full control**: Manual partitioning and config
- **Debuggable**: Can inspect each step

### Steps

1. **Install Nix on Ubuntu**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
     | sh -s -- install --no-confirm
   ```

2. **Wipe disk partition table**
   ```bash
   sudo dd if=/dev/zero of=/dev/sda bs=1M count=10
   sudo reboot
   ```

3. **Create partitions**
   ```bash
   sudo parted -s /dev/sda mklabel gpt
   sudo parted -s /dev/sda mkpart primary fat32 1M 512M
   sudo parted -s /dev/sda mkpart primary ext4 512M 100%
   sudo parted -s /dev/sda set 1 boot on
   ```

4. **Format and mount**
   ```bash
   sudo mkfs.fat -F 32 /dev/sda1
   sudo mkfs.ext4 /dev/sda2
   sudo mount /dev/sda2 /mnt
   sudo mkdir -p /mnt/boot/efi
   sudo mount /dev/sda1 /mnt/boot/efi
   ```

5. **Generate config**
   ```bash
   . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
   sudo nixos-generate-config --root /mnt
   ```

6. **Install NixOS**
   ```bash
   sudo nixos-install --root /mnt --no-root-password
   sudo umount -R /mnt
   sudo reboot
   ```

### Pros
- ✅ Works without special builds
- ✅ Full control over partitioning
- ✅ Can use nix-build directly
- ✅ Debuggable at each step

### Cons
- ❌ Requires Nix installed on Ubuntu first
- ❌ Longer (needs Nix build)
- ❌ May timeout on slow networks

---

## Method 4: LUSTRATE (Legacy, Less Common)

### Why LUSTRATE?
- **In-place conversion**: Converts existing OS to NixOS
- **No reboots**: Stays in same partition scheme

### Issues
- ❌ Limited by existing partition scheme
- ❌ More complex
- ❌ Less documented for ARM64

---

## Comparison Matrix

| Method | Complexity | Speed | Works ARM64 | Documentation |
|--------|-----------|-------|------------|--------------|
| **Kexec** | Medium | Medium (5-10 min) | ✅ Yes | ✅ Excellent |
| **Netboot** | Low | Fast (2-3 min) | ✅ Yes | ✅ Good |
| **Manual** | High | Slow (20-30 min) | ✅ Yes | ✅ Fair |
| **LUSTRATE** | High | Medium | ⚠️ Untested | ❌ Poor |

---

## Key Findings from Community

1. **Kexec is most popular** - Used in most tutorials and guides
2. **Netboot is emerging** - Becoming more popular with recent updates
3. **Manual method works** - More verbose but gives full control
4. **ARM64 is supported** - All methods work on Ampere A1 (free tier)
5. **Download mirrors matter** - Pre-built kexec needs valid URLs

---

## For India Strong (Our Approach)

We chose **Method 3 (Manual)** because:
- ✅ nixos-anywhere kexec failed (known ARM64 issue)
- ✅ We already have Nix installed
- ✅ Full visibility into each step
- ✅ Can debug failures more easily
- ✅ Don't depend on pre-built artifacts

---

## Common Issues

### Kexec Build Not Found
- Pre-built kexec URLs frequently change
- Solution: Build locally or use netboot instead

### Network Timeout During Install
- `nixos-install` downloads large packages
- Solution: Use `--fast-link` flag or be patient

### Partition Table Locked
- OS still using partition
- Solution: Wipe MBR with dd, then reboot

### EFI Boot Menu Not Accessible
- Oracle BIOS may lock it down
- Solution: Use kexec or manual method instead

---

## Community Resources

- **NixOS Wiki**: https://wiki.nixos.org/wiki/Install_NixOS_on_Oracle_Cloud
- **NixOS Discourse**: Topic "Install NixOS on OCI Oracle Cloud"
- **GitHub Gists**: Multiple step-by-step guides (search "oracle-cloud-nixos")
- **Blog Posts**: Multiple personal blogs documenting experiences

---

## Recommendations

1. **If experienced with NixOS**: Use Kexec (most efficient)
2. **If new to NixOS**: Use Netboot or Manual (simpler debugging)
3. **If kexec URLs broken**: Use Manual method (what we're doing)
4. **If ARM64**: All methods work, but kexec is most proven

---

**Last Updated:** 2025-10-19
**Status:** Researched and documented
**Recommended for Uptrack:** Manual method (Method 3)

