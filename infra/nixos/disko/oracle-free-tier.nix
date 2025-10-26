# Oracle Cloud Free Tier disk configuration
# NOTE: Oracle Cloud uses pre-existing partitions, so we DON'T use disko
# This file is a placeholder for documentation purposes only
#
# Oracle partitions are already created and referenced in common/oracle.nix:
# - /dev/disk/by-partlabel/disk-main-root (ext4, mounted at /)
# - /dev/disk/by-partlabel/disk-main-boot (vfat, mounted at /boot)
#
# DO NOT import this file in Oracle node configs!
{ lib, ... }:
{
  # This is intentionally empty - Oracle doesn't use disko
  # See common/oracle.nix for filesystem configuration
}
