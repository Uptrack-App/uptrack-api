#!/usr/bin/env bash
set -e

echo "=== Step 0: Cleaning existing partitions ==="
# Unmount any existing mounts
umount /dev/sda* 2>/dev/null || true

# Remove LVM if exists
vgremove -f hk 2>/dev/null || true
pvremove -f /dev/sda2 2>/dev/null || true

# Wipe the disk completely
wipefs -a /dev/sda

echo "=== Step 1: Checking disk ==="
lsblk

echo "=== Step 2: Partitioning disk ==="
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart primary 1MiB 2MiB
parted /dev/sda -- set 1 bios_grub on
parted /dev/sda -- mkpart primary ext4 2MiB 1026MiB
parted /dev/sda -- mkpart primary ext4 1026MiB 100%

echo "=== Step 3: Formatting partitions ==="
mkfs.ext4 -F -L boot /dev/sda2
mkfs.ext4 -F -L nixos /dev/sda3

echo "=== Step 4: Mounting filesystems ==="
# Use partition paths instead of labels (labels sometimes take time to appear)
mount /dev/sda3 /mnt
mkdir -p /mnt/boot
mount /dev/sda2 /mnt/boot

echo "=== Step 5: Generating config ==="
nixos-generate-config --root /mnt

echo "=== Step 6: Writing configuration ==="
cat > /mnt/etc/nixos/configuration.nix << 'EOF'
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # GRUB bootloader
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # Networking
  networking.hostName = "uptrack-eu-a";
  networking.useDHCP = true;
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

  # Firewall
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # SSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";

  # Root SSH key
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];

  # Nix settings for flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
  ];

  system.stateVersion = "24.11";
}
EOF

echo "=== Step 7: Installing NixOS ==="
nixos-install --no-root-passwd

echo "=== Installation complete! ==="
echo "Next steps:"
echo "1. Go to Hostkey console and click 'Unmount ISO'"
echo "2. Type 'reboot' to restart"
echo "3. SSH back in: ssh root@194.180.207.223"
