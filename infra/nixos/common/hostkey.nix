# Common configuration for Hostkey VPS nodes
{ config, pkgs, lib, ... }:

{
  # Boot loader configuration for BIOS/Legacy boot
  # Note: boot.loader.grub.device is set by disko, don't duplicate it here
  boot.loader.grub = {
    enable = true;
    efiSupport = false;   # BIOS mode, not EFI
  };

  # Boot-time rollback protection
  boot.loader.timeout = 10;  # Show boot menu for 10 seconds to select previous generation

  # Network configuration
  networking = {
    useDHCP = true;
    nameservers = [ "8.8.8.8" "8.8.4.4" ];
  };

  # Firewall - allow SSH and HTTPS
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 443 ];
  };

  # Minimal system packages
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tmux
  ];
}
