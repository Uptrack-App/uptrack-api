# Netcup VPS-specific configuration
# For existing NixOS systems (not fresh installs via nixos-anywhere)
#
# Note: Disko is NOT imported here because it's only for fresh installations.
# The disk is already partitioned; we just need to configure the bootloader
# and filesystem mounts.
{ config, pkgs, lib, ... }:

{
  # Boot loader configuration for Netcup (BIOS, not EFI)
  # Netcup VPS uses BIOS boot with virtio disks (/dev/vda)
  boot.loader.grub = {
    enable = true;
    efiSupport = false;  # BIOS mode, not EFI
    device = "/dev/vda";  # Install GRUB to MBR of virtio disk
  };

  # Filesystem configuration for existing Netcup VPS
  # All nbg nodes have the same partition layout: vda4 = root (ext4)
  fileSystems."/" = {
    device = "/dev/vda4";
    fsType = "ext4";
  };

  # Agenix secrets configuration
  # age.secrets = {
  #   uptrack-env = {
  #     file = ../secrets/uptrack-env.age;
  #   };
  # };

  # Agenix will look for SSH host keys here
  # age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
