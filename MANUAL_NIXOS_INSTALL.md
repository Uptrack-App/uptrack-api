# Manual NixOS Installation for India Strong Node (ARM64 Oracle)

## Overview

This guide uses a manual approach that's more reliable for ARM64 Oracle instances:

1. **Boot into NixOS live environment** (via curl script)
2. **Partition and format disks** manually
3. **Install NixOS** using `nixos-install`
4. **Configure services** via Nix flake
5. **Boot into NixOS**

This approach gives us **more control** than nixos-anywhere on ARM64 systems.

---

## Prerequisites

✅ SSH access as ubuntu user
✅ Disk available: 46.6 GB
✅ RAM available: 17 GB
✅ Network working: 10.0.0.198/24

---

## Step 1: Download NixOS ARM64 Image and Boot via Kexec

SSH to the instance and run:

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Download NixOS 25.05 ARM64 image
cd /tmp
curl -L https://hydra.nixos.org/build/290180491/download/1/nixos-sd-image-25.05pre-git-aarch64-linux.img.zst \
  -o nixos-image.img.zst

# Decompress
zstd -d nixos-image.img.zst
```

---

## Step 2: Boot into NixOS Live Environment

```bash
# Check available disk
lsblk

# Burn image to disk (assuming /dev/sda)
sudo dd if=nixos-image.img of=/dev/sda bs=4M conv=fsync

# Reboot
sudo reboot
```

---

## Step 3: After Reboot - NixOS Live Environment

After reboot, SSH will be available. Connect as root:

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
```

---

## Step 4: Partition and Format Disks

In the NixOS live environment:

```bash
# Verify disk
lsblk

# Partition the disk (assuming /dev/sda)
sudo fdisk /dev/sda

# Delete all partitions (d, d, d...)
# Create new partitions:
# 1. EFI partition: +500M (type EF)
# 2. Root partition: rest (type 83 - Linux)

# Format partitions
sudo mkfs.fat -F 32 /dev/sda1
sudo mkfs.ext4 /dev/sda2

# Mount partitions
sudo mount /dev/sda2 /mnt
sudo mkdir -p /mnt/boot/efi
sudo mount /dev/sda1 /mnt/boot/efi
```

---

## Step 5: Generate NixOS Configuration

```bash
# Generate basic NixOS config
sudo nixos-generate-config --root /mnt

# This creates:
# - /mnt/etc/nixos/hardware-configuration.nix
# - /mnt/etc/nixos/configuration.nix
```

---

## Step 6: Customize Configuration

Edit `/mnt/etc/nixos/configuration.nix`:

```nix
{ config, pkgs, ... }:

{
  imports =
    [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "uptrack-node-india-strong";
  networking.useDHCP = true;

  # Enable SSH
  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    curl
    git
  ];

  system.stateVersion = "25.05";
}
```

---

## Step 7: Install NixOS

```bash
# Install NixOS to /mnt
sudo nixos-install --root /mnt

# This will:
# - Build NixOS from configuration
# - Install to /mnt
# - Takes 10-20 minutes
```

---

## Step 8: Boot into NixOS

```bash
# Unmount
sudo umount -R /mnt

# Reboot
sudo reboot
```

---

## Step 9: After NixOS Boot - Deploy Full Configuration

Once in NixOS, clone repo and deploy:

```bash
# SSH as root
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Clone repo
cd /root
git clone https://github.com/your-repo/uptrack.git

# Copy flake configuration
cd uptrack

# Build and activate configuration
sudo nixos-rebuild switch --flake .#node-india-strong
```

---

## Automated Script (Recommended)

Instead of manual steps, use this script to automate the process:

```bash
# See: manual-nixos-install.sh
bash /Users/le/repos/uptrack/manual-nixos-install.sh
```

---

## Troubleshooting

### Issue 1: Can't Download NixOS Image

Try alternative mirrors:

```bash
# Mirror 1
https://hydra.nixos.org/build/290180491/download/1/nixos-sd-image-25.05pre-git-aarch64-linux.img.zst

# Mirror 2
https://nixos.org/releases/nixos/unstable-aarch64-linux/latest-nixos-sd-image-aarch64-linux.img.zst

# Mirror 3
https://tarballs.nixos.org/unstable-aarch64-linux/latest-nixos-sd-image-aarch64-linux.img.zst
```

### Issue 2: Partition Errors

Use `parted` instead of `fdisk`:

```bash
sudo parted /dev/sda
# mklabel gpt
# mkpart primary fat32 1M 512M
# mkpart primary ext4 512M 100%
# set 1 boot on
# quit
```

### Issue 3: SSH Key Not Authorized

The live environment might not have your SSH key. Add it:

```bash
# From live environment, authorized_keys might be empty
# Add your public key manually or via SSH command
```

### Issue 4: Installation Takes Too Long

This is normal on slow connections. Give it 20-30 minutes.

---

## Files Reference

- `manual-nixos-install.sh` - Automated script for all steps
- `/mnt/etc/nixos/hardware-configuration.nix` - Generated hardware config
- `/mnt/etc/nixos/configuration.nix` - NixOS system config
- `flake.nix` - Your Uptrack flake configuration

---

**Estimated Time**: 45-60 minutes total

