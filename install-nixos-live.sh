#!/bin/bash

# NixOS Installation Script (Run in NixOS Live Environment)
# This script installs NixOS to the system

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}━━━ $1${NC}"
}

main() {
    print_header "NixOS Installation (Running in Live Environment)"

    print_step "Step 1: Verify Disk"
    print_info "Checking available disks..."
    lsblk
    read -p "Which disk to install to? (e.g., sda): " DISK
    DISK_PATH="/dev/$DISK"

    if [ ! -b "$DISK_PATH" ]; then
        print_error "Disk not found: $DISK_PATH"
        exit 1
    fi

    print_warn "⚠️  Will format $DISK_PATH - this is IRREVERSIBLE!"
    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Installation cancelled"
        exit 0
    fi

    print_step "Step 2: Create Partitions"
    print_info "Creating EFI and root partitions..."

    # Create partitions
    parted -s "$DISK_PATH" mklabel gpt
    parted -s "$DISK_PATH" mkpart primary fat32 1M 512M
    parted -s "$DISK_PATH" mkpart primary ext4 512M 100%
    parted -s "$DISK_PATH" set 1 boot on

    print_info "✓ Partitions created"

    print_step "Step 3: Format Partitions"
    print_info "Formatting EFI partition..."
    mkfs.fat -F 32 "${DISK_PATH}1"

    print_info "Formatting root partition..."
    mkfs.ext4 "${DISK_PATH}2"

    print_info "✓ Partitions formatted"

    print_step "Step 4: Mount Partitions"
    print_info "Mounting partitions..."
    mount "${DISK_PATH}2" /mnt
    mkdir -p /mnt/boot/efi
    mount "${DISK_PATH}1" /mnt/boot/efi

    print_info "✓ Partitions mounted"

    print_step "Step 5: Generate NixOS Configuration"
    print_info "Generating hardware configuration..."
    nixos-generate-config --root /mnt

    print_info "✓ Configuration generated at /mnt/etc/nixos/"

    print_step "Step 6: Customize Configuration"
    print_info "Current configuration:"
    echo "  - Hardware: /mnt/etc/nixos/hardware-configuration.nix"
    echo "  - System: /mnt/etc/nixos/configuration.nix"
    echo ""
    print_info "Edit configuration if needed:"
    read -p "Edit configuration now? (yes/no): " edit_config
    if [ "$edit_config" = "yes" ]; then
        nano /mnt/etc/nixos/configuration.nix
    fi

    print_step "Step 7: Install NixOS"
    print_warn "This will take 10-20 minutes..."
    print_info "Installing NixOS to /mnt..."

    nixos-install --root /mnt

    print_info "✓ NixOS installed"

    print_step "Step 8: Cleanup and Reboot"
    print_info "Unmounting filesystems..."
    umount -R /mnt

    echo ""
    print_header "Installation Complete! ✅"
    print_info "NixOS has been successfully installed"
    print_info "Rebooting in 10 seconds..."
    sleep 10

    reboot
}

# Run main
main "$@"
