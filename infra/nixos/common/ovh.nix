# OVH VPS-specific configuration
# Handles OVH VPS-1 server specifics
{ config, pkgs, lib, ... }:

{
  # Import disko for disk configuration
  imports = [ ../disko/ovh-vps1.nix ];

  # Boot loader configuration for OVH (EFI)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    # Don't set 'device' when using EFI - disko handles it
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
