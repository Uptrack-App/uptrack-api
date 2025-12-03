# Disko configuration for Hostkey VPS - BIOS/MBR boot
# Use this for servers that boot in BIOS/Legacy mode (not UEFI)
{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";  # Hostkey uses /dev/sda
        content = {
          type = "gpt";  # Use GPT even for BIOS (modern, supports >2TB, better than MBR)
          partitions = {
            # BIOS boot partition (required for GRUB on GPT)
            bios = {
              size = "1M";
              type = "EF02";  # BIOS boot partition type
            };
            # Boot partition
            boot = {
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/boot";
              };
            };
            # Root partition
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
