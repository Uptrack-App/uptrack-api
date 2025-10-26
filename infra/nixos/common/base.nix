# Base NixOS configuration shared across ALL servers
# This is the foundation that all nodes inherit from
{ config, pkgs, lib, ... }:

{
  # Allow unfree packages (needed for some tools)
  nixpkgs.config.allowUnfree = true;

  # Ensure initrd includes necessary kernel modules for all providers
  boot.initrd.availableKernelModules = [
    "ahci" "xhci_pci" "virtio_pci" "virtio_blk" "virtio_scsi"
    "sd_mod" "sr_mod" "ata_piix" "nvme"
  ];
  boot.kernelModules = [ ];

  # Enable systemd in initrd for better device detection
  boot.initrd.systemd.enable = true;

  # Networking
  networking = {
    # Hostname will be set per-machine
    useDHCP = lib.mkDefault true;

    # Enable firewall
    firewall = {
      enable = true;
      # Default: deny all incoming, allow all outgoing
      # Specific ports opened per-service
    };
  };

  # Timezone and locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # System packages available globally
  environment.systemPackages = with pkgs; [
    # Essential tools
    vim
    git
    curl
    wget
    htop
    tmux
    rsync

    # Debugging
    lsof
    strace
    tcpdump
    iotop
    sysstat

    # Useful utilities
    jq
    ripgrep
    fd
    tree
    netcat
  ];

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };

    # Only allow key-based authentication
    openFirewall = true;
  };

  # Security settings
  security = {
    sudo.wheelNeedsPassword = false;  # Convenient for automation
  };

  # User configuration
  users.users.root.openssh.authorizedKeys.keys = [
    # Your SSH public key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
  ];

  # Automatic garbage collection
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      download-buffer-size = 134217728; # Enlarge fetch buffer
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Automatic system updates (disabled - we use Colmena)
  system.autoUpgrade = {
    enable = false;
    allowReboot = false;
  };

  # This value determines the NixOS release
  system.stateVersion = "24.11";
}
