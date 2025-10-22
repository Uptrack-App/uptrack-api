# Common NixOS configuration for Oracle Cloud servers
# Same as common.nix but WITHOUT disko (Oracle doesn't use disko partitioning)
{ config, pkgs, lib, ... }:

{
  # NO disko import for Oracle Cloud - partitions already exist

  # Filesystem configuration for Oracle Cloud
  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/disk-main-root";
    fsType = "ext4";
    options = [ "x-initrd.mount" "defaults" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/disk-main-boot";
    fsType = "vfat";
    options = [ "defaults" ];
  };

  # Agenix secrets configuration
  # Temporarily disabled until we have the server SSH host key
  # After installation, add the host key to secrets.nix and create uptrack-env.age
  # age.secrets = {
  #   uptrack-env = {
  #     file = ./secrets/uptrack-env.age;
  #   };
  # };

  # Agenix will look for SSH host keys here
  # age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Allow unfree packages (needed for some tools)
  nixpkgs.config.allowUnfree = true;

  # Boot loader configuration for Oracle Cloud
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";  # Oracle uses MBR GRUB on /dev/sda
    efiSupport = false;   # No EFI on Oracle Free Tier
  };

  # Ensure initrd includes necessary kernel modules
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
  users.users.root = {
    openssh.authorizedKeys.keys = [
      # Your SSH public key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"
    ];
  };

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
