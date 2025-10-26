# Contabo VPS-specific configuration
# Handles Contabo x86_64 server specifics
{ config, pkgs, lib, ... }:

{
  # Import disko for disk configuration
  imports = [ ../disko/contabo-vps.nix ];

  # Boot loader configuration for Contabo (EFI)
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    # Don't set 'device' when using EFI - disko handles it
  };

  # Agenix secrets configuration
  # Temporarily disabled until we have the server SSH host key
  # After installation, add the host key to secrets.nix and create uptrack-env.age
  # age.secrets = {
  #   uptrack-env = {
  #     file = ../secrets/uptrack-env.age;
  #   };
  # };

  # Agenix will look for SSH host keys here
  # age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
