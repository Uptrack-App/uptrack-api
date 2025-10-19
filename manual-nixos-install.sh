#!/bin/bash

# Manual NixOS Installation for ARM64 Oracle Instance
# This script automates the nixos-install approach

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

# Configuration
INDIA_STRONG_IP="144.24.133.171"
SSH_KEY="/Users/le/.ssh/ssh-key-2025-10-18.key"
NIXOS_IMAGE_URL="https://hydra.nixos.org/build/290180491/download/1/nixos-sd-image-25.05pre-git-aarch64-linux.img.zst"

# Functions
run_remote_command() {
    ssh -i "$SSH_KEY" -o ConnectTimeout=10 "$1" "$2"
}

# Main execution
main() {
    print_header "Manual NixOS Installation for India Strong (ARM64)"

    print_step "Step 1: Connect and Download NixOS Image"
    print_info "Connecting to instance as ubuntu..."

    # Test connectivity
    if ! run_remote_command "ubuntu@$INDIA_STRONG_IP" "echo 'Connected'" >/dev/null 2>&1; then
        print_error "Cannot connect to $INDIA_STRONG_IP as ubuntu"
        exit 1
    fi
    print_info "✓ Connected"

    print_info "Downloading NixOS 25.05 ARM64 image (this may take 5-10 min)..."
    run_remote_command "ubuntu@$INDIA_STRONG_IP" "cd /tmp && \
        curl -L '$NIXOS_IMAGE_URL' -o nixos-image.img.zst && \
        echo 'Download complete' && \
        ls -lh nixos-image.img.zst"

    print_info "✓ Image downloaded"

    print_step "Step 2: Decompress NixOS Image"
    print_info "Decompressing image (this may take 2-3 min)..."
    run_remote_command "ubuntu@$INDIA_STRONG_IP" "cd /tmp && \
        zstd -d nixos-image.img.zst && \
        echo 'Decompression complete' && \
        ls -lh nixos-image.img"

    print_info "✓ Image decompressed"

    print_step "Step 3: Verify Disk Layout"
    print_info "Checking available disk..."
    run_remote_command "ubuntu@$INDIA_STRONG_IP" "lsblk"

    echo ""
    print_step "Step 4: Write Image to Disk and Reboot"
    print_warn "⚠️  WARNING: This will OVERWRITE /dev/sda"
    print_warn "⚠️  All data on the instance will be ERASED"
    read -p "Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Installation cancelled"
        exit 0
    fi

    print_info "Writing NixOS image to /dev/sda (this takes 3-5 min)..."
    run_remote_command "ubuntu@$INDIA_STRONG_IP" "cd /tmp && \
        sudo dd if=nixos-image.img of=/dev/sda bs=4M conv=fsync && \
        echo 'Image written successfully'"

    print_info "✓ Image written"

    echo ""
    print_info "Rebooting instance..."
    print_warn "SSH will be unavailable for 2-3 minutes"

    run_remote_command "ubuntu@$INDIA_STRONG_IP" "sudo reboot" || true

    sleep 5
    print_info "Waiting for system to boot NixOS (3-5 minutes)..."

    for i in {60..1}; do
        if ssh -i "$SSH_KEY" -o ConnectTimeout=5 root@"$INDIA_STRONG_IP" "echo 'NixOS online'" >/dev/null 2>&1; then
            print_info "✓ NixOS live environment online"
            break
        fi
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
        sleep 5
    done

    echo ""
    print_step "Step 5: NixOS Live Environment - Ready for Installation"
    print_info "✓ You're now in NixOS live environment"
    print_info "✓ SSH as root is available"
    echo ""
    print_info "Next manual steps:"
    echo "  1. SSH to the instance:"
    echo "     ssh -i $SSH_KEY root@$INDIA_STRONG_IP"
    echo ""
    echo "  2. Run the live installation script:"
    echo "     bash /root/install-nixos.sh"
    echo ""
    echo "  Or follow the manual steps in MANUAL_NIXOS_INSTALL.md"
    echo ""
}

# Run main
main "$@"
