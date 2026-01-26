# Netcup VPS-specific configuration
# Handles Netcup VPS server specifics (BIOS boot, virtio disks)
{ config, pkgs, lib, ... }:

{
  # Import disko for disk configuration
  imports = [ ../disko/netcup-arm-g11.nix ];

  # Boot loader configuration for Netcup (BIOS, not EFI)
  # Netcup VPS uses BIOS boot with virtio disks (/dev/vda)
  boot.loader.grub = {
    enable = true;
    efiSupport = false;  # BIOS mode, not EFI
    # Device is set via disko.devices.disk.main.device in node configs
    device = lib.mkDefault "/dev/vda";
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
