# NixOS Manual Installation Guide - Hostkey (BIOS Boot)

**For**: Hostkey Italy VPS (BIOS boot, /dev/sda)
**Node**: eu-a (REMOVED_IP)
**Date**: 2025-11-02

---

## Pre-Installation (You're already here!)

✅ Booted from NixOS ISO
✅ Logged in as root
✅ Network configured (REMOVED_IP)

---

## Step 1: Partition the Disk

```bash
# Wipe existing partitions and create new GPT table
parted /dev/sda -- mklabel gpt

# Create BIOS boot partition (1MB, required for GRUB on GPT)
parted /dev/sda -- mkpart primary 1MB 2MB
parted /dev/sda -- set 1 bios_grub on

# Create boot partition (1GB)
parted /dev/sda -- mkpart primary 2MB 1GB

# Create root partition (rest of disk)
parted /dev/sda -- mkpart primary 1GB 100%

# Verify partitions
parted /dev/sda -- print
```

**Expected output**:
```
Number  Start   End     Size    File system  Name     Flags
1       1.00MB  2.00MB  1.00MB               primary  bios_grub
2       2.00MB  1000MB  998MB                primary
3       1000MB  120GB   119GB                primary
```

---

## Step 2: Format Partitions

```bash
# Format boot partition (ext4)
mkfs.ext4 -L boot /dev/sda2

# Format root partition (ext4)
mkfs.ext4 -L nixos /dev/sda3

# Verify
lsblk -f
```

---

## Step 3: Mount Partitions

```bash
# Mount root
mount /dev/disk/by-label/nixos /mnt

# Create boot directory
mkdir -p /mnt/boot

# Mount boot
mount /dev/disk/by-label/boot /mnt/boot

# Verify mounts
df -h | grep /mnt
```

---

## Step 4: Generate Initial Configuration

```bash
# Generate hardware and base configuration
nixos-generate-config --root /mnt

# This creates:
# - /mnt/etc/nixos/configuration.nix
# - /mnt/etc/nixos/hardware-configuration.nix
```

---

## Step 5: Edit Configuration

```bash
# Open the configuration file
nano /mnt/etc/nixos/configuration.nix
```

**Replace ENTIRE contents with this:**

```nix
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Boot loader for BIOS
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # Hostname
  networking.hostName = "uptrack-eu-a";

  # Enable DHCP
  networking.useDHCP = true;

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 443 ];
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Root user SSH key
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tmux
    tailscale
  ];

  # Enable Tailscale
  services.tailscale.enable = true;

  # NixOS version
  system.stateVersion = "24.11";
}
```

**To save in nano**:
- Press `Ctrl+O` (write out)
- Press `Enter` (confirm filename)
- Press `Ctrl+X` (exit)

---

## Step 6: Install NixOS

```bash
# Start the installation (this will take 10-15 minutes)
nixos-install

# When prompted for root password, enter: REMOVED_PASSWORD
# (You can change this later)
```

**What happens during installation:**
- Downloads NixOS packages
- Installs system
- Installs GRUB bootloader
- Generates /boot/grub/grub.cfg

**Expected output at the end:**
```
installation finished!
```

---

## Step 7: Reboot

```bash
# Reboot into the new system
reboot
```

**After reboot:**
1. Server will restart
2. Go back to Hostkey panel
3. **Click "Unmount ISO"** (important!)
4. Server will boot from disk into NixOS
5. Wait 1-2 minutes for boot

---

## Step 8: Verify Installation (After Reboot)

From your local machine:

```bash
# SSH into the new NixOS system
ssh root@REMOVED_IP

# Check NixOS version
nixos-version

# Check Tailscale is installed
tailscale version

# Start Tailscale
tailscale up --auth-key=REMOVED_TAILSCALE_AUTH_KEY --hostname=eu-a
```

---

## Troubleshooting

### If installation fails at GRUB installation:
```bash
# Manually install GRUB
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
```

### If boot fails:
1. Boot from ISO again
2. Mount partitions: `mount /dev/sda3 /mnt && mount /dev/sda2 /mnt/boot`
3. Enter chroot: `nixos-enter`
4. Fix configuration: `nano /etc/nixos/configuration.nix`
5. Reinstall: `nixos-rebuild switch`

### If network doesn't work after boot:
```bash
# Check interface name
ip link show

# If it changed from enp2s1 to something else, update:
# nano /etc/nixos/configuration.nix
# Add: networking.interfaces.NEW_NAME.useDHCP = true;
```

---

## Summary of Commands (Quick Reference)

```bash
# 1. Partition
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 1MB 2MB
parted /dev/sda -- set 1 bios_grub on
parted /dev/sda -- mkpart primary 2MB 1GB
parted /dev/sda -- mkpart primary 1GB 100%

# 2. Format
mkfs.ext4 -L boot /dev/sda2
mkfs.ext4 -L nixos /dev/sda3

# 3. Mount
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot

# 4. Generate config
nixos-generate-config --root /mnt

# 5. Edit config (use nano)
nano /mnt/etc/nixos/configuration.nix

# 6. Install
nixos-install

# 7. Reboot
reboot
```

---

**Good luck! This should take about 15-20 minutes total.**
