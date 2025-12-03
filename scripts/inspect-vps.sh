#!/usr/bin/env bash
# VPS Inspection Script for NixOS Deployment Planning
# Usage: ./inspect-vps.sh <hostname_or_ip> [ssh_key_path]
#
# This script gathers critical information about a VPS before attempting NixOS installation
# to avoid compatibility issues with nixos-anywhere and disko.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

HOST="${1:-}"
SSH_KEY="${2:-$HOME/.ssh/id_ed25519}"

if [ -z "$HOST" ]; then
    echo -e "${RED}Error: No hostname provided${NC}"
    echo "Usage: $0 <hostname_or_ip> [ssh_key_path]"
    exit 1
fi

echo -e "${BLUE}=== VPS Inspection Report ===${NC}"
echo "Target: $HOST"
echo "Date: $(date)"
echo ""

# Test SSH connectivity
echo -e "${YELLOW}[1/10] Testing SSH connectivity...${NC}"
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$HOST" "echo 'SSH OK'" &>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    exit 1
fi

# Function to run remote command
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no root@"$HOST" "$@"
}

# 1. Boot Mode Detection
echo -e "\n${YELLOW}[2/10] Detecting boot mode...${NC}"
BOOT_MODE=$(run_remote '[ -d /sys/firmware/efi ] && echo "UEFI" || echo "BIOS"')
echo "Boot Mode: ${BOOT_MODE}"
if [ "$BOOT_MODE" == "UEFI" ]; then
    echo -e "${GREEN}✓ UEFI boot detected (recommended)${NC}"
else
    echo -e "${YELLOW}⚠ BIOS/Legacy boot detected (requires special disko config)${NC}"
fi

# 2. Operating System
echo -e "\n${YELLOW}[3/10] Detecting operating system...${NC}"
run_remote "cat /etc/os-release | grep -E '^(NAME|VERSION_ID|ID)='" || echo "Could not detect OS"

# 3. Kernel Version
echo -e "\n${YELLOW}[4/10] Kernel version...${NC}"
run_remote "uname -r"

# 4. Disk Information
echo -e "\n${YELLOW}[5/10] Disk layout...${NC}"
run_remote "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT"

echo -e "\n${YELLOW}[5b/10] Disk devices...${NC}"
run_remote "ls -la /dev/sd* /dev/vd* /dev/nvme* 2>/dev/null || echo 'No standard disk devices found'"

# 5. Partition Table Type
echo -e "\n${YELLOW}[6/10] Partition table type...${NC}"
MAIN_DISK=$(run_remote "lsblk -ndo NAME | head -1")
echo "Main disk: /dev/$MAIN_DISK"
run_remote "fdisk -l /dev/$MAIN_DISK 2>/dev/null | grep -i 'disklabel type' || parted -l 2>/dev/null | grep -i 'partition table'" || echo "Could not determine partition table type"

# 6. Memory
echo -e "\n${YELLOW}[7/10] Memory information...${NC}"
run_remote "free -h | grep -E '^(Mem|Swap):'"

# 7. CPU Information
echo -e "\n${YELLOW}[8/10] CPU information...${NC}"
run_remote "lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Virtualization)'"

# 8. Network Configuration
echo -e "\n${YELLOW}[9/10] Network configuration...${NC}"
run_remote "ip -4 addr show | grep -E '^[0-9]+:|inet '"

echo -e "\n${YELLOW}[9b/10] Default gateway...${NC}"
run_remote "ip route show default"

# 9. Kexec Compatibility Test
echo -e "\n${YELLOW}[10/10] Kexec availability (for nixos-anywhere)...${NC}"
if run_remote "command -v kexec &>/dev/null"; then
    echo -e "${GREEN}✓ kexec command available${NC}"
    run_remote "kexec --version 2>&1 | head -1" || echo "kexec found but version unknown"
else
    echo -e "${YELLOW}⚠ kexec not installed (nixos-anywhere will install it)${NC}"
fi

# 10. Virtualization Detection
echo -e "\n${YELLOW}[11/10] Virtualization platform...${NC}"
VIRT=$(run_remote "systemd-detect-virt 2>/dev/null || echo 'unknown'")
echo "Virtualization: $VIRT"

# Summary and Recommendations
echo -e "\n${BLUE}=== Summary ===${NC}"
echo -e "Boot Mode: ${BOOT_MODE}"
echo -e "Main Disk: /dev/${MAIN_DISK}"
echo -e "Virtualization: ${VIRT}"

echo -e "\n${BLUE}=== Recommendations for NixOS Installation ===${NC}"

if [ "$BOOT_MODE" == "UEFI" ]; then
    echo -e "${GREEN}✓ Use EFI/UEFI disko configuration${NC}"
    echo "  Recommended: infra/nixos/disko/hostkey-standard.nix (with EFI)"
else
    echo -e "${YELLOW}⚠ Use BIOS/Legacy disko configuration${NC}"
    echo "  Recommended: infra/nixos/disko/hostkey-bios.nix"
fi

echo -e "\n${BLUE}=== Disko Configuration Template ===${NC}"
if [ "$BOOT_MODE" == "BIOS" ]; then
    cat <<'EOF'
# BIOS Boot Configuration
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/DISK_NAME";  # Replace with actual disk
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";  # BIOS boot partition
        };
        boot = {
          size = "1G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/boot";
          };
        };
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
  boot.loader.grub.device = "/dev/DISK_NAME";
}
EOF
else
    cat <<'EOF'
# UEFI Boot Configuration
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/DISK_NAME";  # Replace with actual disk
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
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
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
}
EOF
fi

echo -e "\n${BLUE}=== Next Steps ===${NC}"
echo "1. Review the boot mode and disk configuration above"
echo "2. Create appropriate disko configuration for this VPS"
echo "3. Test nixos-anywhere with: nix run github:nix-community/nixos-anywhere -- --flake '.#config-name' root@$HOST"
echo "4. If kexec fails (network unreachable), consider manual installation or ISO boot"

echo -e "\n${GREEN}Inspection complete!${NC}"
