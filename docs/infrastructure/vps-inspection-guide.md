# VPS Inspection Guide for NixOS Deployment

**Purpose**: Standardized inspection process for new VPS servers before attempting NixOS installation to avoid compatibility issues.

**Date Created**: 2025-11-02
**Last Updated**: 2025-11-02

---

## Quick Start

```bash
# Make the script executable
chmod +x scripts/inspect-vps.sh

# Run inspection
./scripts/inspect-vps.sh <vps_ip> [ssh_key_path]

# Example
./scripts/inspect-vps.sh 194.180.207.223 ~/.ssh/id_ed25519
```

---

## Why We Need This

During Hostkey deployment (2025-11-02), we encountered:
- ❌ **nixos-anywhere kexec failures** - network became unreachable after kexec
- ❌ **Boot mode mismatch** - servers used BIOS but config assumed UEFI
- ❌ **GRUB configuration conflicts** - duplicated device declarations

**This inspection prevents these issues** by gathering critical information upfront.

---

## What the Script Checks

### 1. Boot Mode (BIOS vs UEFI)
**Why it matters**: Determines boot loader and partition layout

**Detection method**:
```bash
[ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"
```

**Implications**:
- **UEFI**: Can use GPT + EFI System Partition (ESP), modern
- **BIOS**: Needs BIOS boot partition (type EF02) or MBR, legacy

### 2. Disk Layout
**Why it matters**: Identifies disk device names and current partitioning

**Checks**:
- Device name (`/dev/sda`, `/dev/vda`, `/dev/nvme0n1`)
- Current partition table (MBR/DOS vs GPT)
- Existing filesystems and mount points

### 3. Operating System
**Why it matters**: Determines installation approach

**Supported**:
- Debian/Ubuntu → nixos-anywhere compatible
- NixOS → use nixos-rebuild instead
- Others → may need manual installation

### 4. Virtualization Platform
**Why it matters**: Some hypervisors have kexec issues

**Known issues**:
- Some OpenVZ containers don't support kexec
- Certain KVM configurations may fail network after kexec

### 5. Network Configuration
**Why it matters**: Kexec must preserve network settings

**Checks**:
- Primary interface name
- IP addressing (DHCP vs static)
- Default gateway

### 6. Memory & CPU
**Why it matters**: Resource planning for builds

**Recommendations**:
- Minimum 2GB RAM for NixOS installation
- Minimum 10GB disk space for base system

---

## Inspection Results Interpretation

### Boot Mode: UEFI ✅
```yaml
Recommended Disko: EFI configuration
Boot Loader: GRUB with EFI support
Partition Table: GPT
```

**Configuration template**:
```nix
boot.loader.grub = {
  enable = true;
  efiSupport = true;
  efiInstallAsRemovable = true;
};

disko.devices.disk.main.content.type = "gpt";
disko.devices.disk.main.content.partitions.ESP = {
  size = "512M";
  type = "EF00";  # EFI System Partition
};
```

---

### Boot Mode: BIOS ⚠️
```yaml
Recommended Disko: BIOS configuration
Boot Loader: GRUB to MBR
Partition Table: GPT with BIOS boot partition
```

**Configuration template**:
```nix
boot.loader.grub.device = "/dev/sda";  # Set via disko

disko.devices.disk.main.content.type = "gpt";
disko.devices.disk.main.content.partitions.bios = {
  size = "1M";
  type = "EF02";  # BIOS boot partition
};
```

---

### Virtualization: KVM ✅
```yaml
Compatibility: Good
Kexec Support: Usually works
Recommendation: Safe to use nixos-anywhere
```

---

### Virtualization: OpenVZ ❌
```yaml
Compatibility: Poor
Kexec Support: Often fails
Recommendation: Manual installation or provider ISO
```

---

## Decision Matrix

| Boot Mode | Disk Type | Virtualization | Installation Method | Disko Config |
|-----------|-----------|----------------|---------------------|--------------|
| UEFI | Any | KVM/Xen | nixos-anywhere | `hostkey-standard.nix` (EFI) |
| BIOS | Any | KVM/Xen | nixos-anywhere | `hostkey-bios.nix` |
| Either | Any | OpenVZ | ❌ Not recommended | N/A |
| UEFI | Any | Unknown | Test kexec first | `hostkey-standard.nix` |
| BIOS | Any | Unknown | Test kexec first | `hostkey-bios.nix` |

---

## Known Provider Configurations

### Hostkey (Italy)
```yaml
Boot Mode: BIOS
Disk Device: /dev/sda
Partition Table: DOS (MBR on Ubuntu/Debian)
Virtualization: KVM
Kexec Compatibility: ❌ FAILS (network unreachable)
Recommended Approach: Manual installation or Debian → NixOS migration
```

**Lessons Learned**:
- Hostkey's kexec doesn't preserve network configuration
- Network becomes completely unreachable after kexec
- Must use alternative installation method (ISO or manual)

### Oracle Cloud (India)
```yaml
Boot Mode: UEFI
Disk Device: /dev/sda
Partition Table: GPT
Virtualization: KVM
Kexec Compatibility: ✅ Works
Recommended Approach: nixos-anywhere
```

### Hetzner Cloud
```yaml
Boot Mode: UEFI
Disk Device: /dev/sda or /dev/vda
Partition Table: GPT
Virtualization: KVM
Kexec Compatibility: ✅ Works
Recommended Approach: nixos-anywhere
```

### Contabo VPS
```yaml
Boot Mode: BIOS
Disk Device: /dev/sda
Partition Table: GPT
Virtualization: KVM
Kexec Compatibility: ⚠️ Sometimes fails
Recommended Approach: Test first, fallback to ISO
```

---

## Installation Workflow

### Step 1: Inspect
```bash
./scripts/inspect-vps.sh <vps_ip>
```

### Step 2: Create Disko Config
Based on inspection results, create appropriate disko configuration:

**For UEFI**:
```bash
cp infra/nixos/disko/hostkey-standard.nix infra/nixos/disko/new-provider.nix
# Edit device paths if needed
```

**For BIOS**:
```bash
cp infra/nixos/disko/hostkey-bios.nix infra/nixos/disko/new-provider.nix
# Edit device paths if needed
```

### Step 3: Create Node Configuration
```bash
mkdir -p infra/nixos/regions/<region>/<node-name>
cp infra/nixos/regions/europe/hostkey-a/default.nix infra/nixos/regions/<region>/<node-name>/default.nix
# Edit hostname, IP, and node-specific settings
```

### Step 4: Add to Flake
```nix
# In flake.nix
nixosConfigurations.<node-name> = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    diskoModule
    agenixModule
    ./infra/nixos/regions/<region>/<node-name>
    ./infra/nixos/disko/new-provider.nix
  ];
  specialArgs = { inherit self; };
};
```

### Step 5: Test Build
```bash
nix build '.#nixosConfigurations.<node-name>.config.system.build.toplevel' --dry-run
```

### Step 6: Attempt Installation
```bash
# Try nixos-anywhere first
nix run github:nix-community/nixos-anywhere -- --flake '.#<node-name>' root@<vps_ip>

# If kexec fails (network unreachable), use alternative method:
# - Boot from provider's NixOS ISO
# - Manual installation via rescue mode
# - Install Debian/Ubuntu first, deploy services, migrate later
```

---

## Troubleshooting

### Kexec Fails (Network Unreachable)
**Symptoms**:
- SSH connects initially
- After kexec message, connection times out
- Network shows "Network is unreachable"

**Solutions**:
1. **Boot from NixOS ISO** (if provider offers it)
2. **Manual installation** via rescue mode
3. **Temporary solution**: Deploy on Debian/Ubuntu, migrate to NixOS later

### Boot Loader Configuration Errors
**Error**: `Failed assertions: - You cannot have duplicated devices in mirroredBoots`

**Cause**: Both disko and NixOS config setting `boot.loader.grub.device`

**Solution**: Let disko handle device configuration
```nix
# In common config - remove device specification
boot.loader.grub.enable = true;  # Only enable, don't set device

# In disko config - set device
boot.loader.grub.device = "/dev/sda";
```

### Partition Table Mismatch
**Error**: Installation fails with partition errors

**Cause**: Disko tries to create GPT but disk has MBR (or vice versa)

**Solution**:
1. Back up any data
2. Ensure disko config matches intended partition table
3. nixos-anywhere will wipe and repartition (destructive!)

---

## Best Practices

### 1. Always Inspect First
Never attempt NixOS installation without running the inspection script.

### 2. Document Provider Quirks
If you discover provider-specific issues, document them in this guide.

### 3. Test on One Node First
When deploying to multiple nodes from the same provider, test installation on one node before deploying to all.

### 4. Keep Backup Plans
Have alternative installation methods ready:
- Provider ISO mounting
- Rescue system access
- Temporary Debian/Ubuntu deployment

### 5. Preserve Network Configuration
If kexec fails due to network issues, the server is likely unrecoverable remotely. You'll need:
- Console access (VNC/KVM)
- Out-of-band management
- Provider support to reboot/reinstall

---

## Checklist Template

Before deploying to a new VPS provider:

- [ ] Run `./scripts/inspect-vps.sh <ip>`
- [ ] Document boot mode (UEFI/BIOS)
- [ ] Document disk device name
- [ ] Document virtualization platform
- [ ] Create appropriate disko configuration
- [ ] Create node configuration
- [ ] Add to flake.nix
- [ ] Test build with `nix build --dry-run`
- [ ] Test installation on single node
- [ ] Document any provider-specific quirks
- [ ] Update this guide with findings
- [ ] Deploy to remaining nodes

---

## Future Improvements

- [ ] Automated kexec compatibility test
- [ ] Provider database with known configurations
- [ ] Pre-flight checklist automation
- [ ] Network configuration preservation detection
- [ ] Rollback plan generation

---

## References

- [NixOS Manual - Installation](https://nixos.org/manual/nixos/stable/#sec-installation)
- [nixos-anywhere Documentation](https://github.com/nix-community/nixos-anywhere)
- [disko Documentation](https://github.com/nix-community/disko)
- [GRUB Boot Loader](https://www.gnu.org/software/grub/)
- [GPT vs MBR](https://en.wikipedia.org/wiki/GUID_Partition_Table)

---

**Maintained by**: Uptrack Infrastructure Team
**Last Inspection**: Hostkey Italy (2025-11-02) - BIOS boot, kexec incompatible
