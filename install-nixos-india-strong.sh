#!/bin/bash

# NixOS Installation Script for India Strong Node
# This script automates the nixos-anywhere installation process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INDIA_STRONG_IP="144.24.133.171"
SSH_KEY="/Users/le/.ssh/ssh-key-2025-10-18.key"
REPO_DIR="/Users/le/repos/uptrack"

# Functions
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

# Verify prerequisites
verify_prerequisites() {
    print_header "Step 1: Verifying Prerequisites"

    print_step "Checking SSH key exists"
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    print_info "SSH key found: $SSH_KEY"

    print_step "Checking SSH key permissions"
    PERMS=$(ls -l "$SSH_KEY" | awk '{print $1}')
    if [ "$PERMS" != "-rw-------" ]; then
        print_warn "SSH key permissions are $PERMS (should be -rw-------)"
        print_info "Fixing permissions..."
        chmod 600 "$SSH_KEY"
        print_info "Permissions fixed"
    else
        print_info "SSH key permissions correct: $PERMS"
    fi

    print_step "Testing SSH connectivity"
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 ubuntu@"$INDIA_STRONG_IP" "echo 'SSH works'" >/dev/null 2>&1; then
        print_info "SSH connectivity successful"
    else
        print_error "Cannot connect to $INDIA_STRONG_IP"
        print_info "Make sure:"
        print_info "  1. Oracle instance is RUNNING"
        print_info "  2. Internet Gateway is attached to VCN"
        print_info "  3. Route Table has 0.0.0.0/0 → IGW route"
        print_info "  4. Security List allows SSH port 22"
        exit 1
    fi

    print_step "Checking Nix installation"
    if ! command -v nix &> /dev/null; then
        print_error "Nix is not installed"
        print_info "Install Nix from: https://nixos.org/download.html"
        exit 1
    fi
    print_info "Nix installation found: $(nix --version)"

    print_step "Checking repo directory"
    if [ ! -d "$REPO_DIR" ]; then
        print_error "Repo directory not found: $REPO_DIR"
        exit 1
    fi
    print_info "Repo directory found: $REPO_DIR"

    print_step "Checking flake configuration"
    if [ ! -f "$REPO_DIR/flake.nix" ]; then
        print_error "flake.nix not found"
        exit 1
    fi
    print_info "flake.nix found"

    print_step "Checking node configuration"
    if [ ! -f "$REPO_DIR/infra/nixos/node-india-strong.nix" ]; then
        print_error "node-india-strong.nix not found"
        exit 1
    fi
    print_info "node-india-strong.nix found"

    echo ""
    print_info "✓ All prerequisites verified"
    echo ""
}

# Confirm installation
confirm_installation() {
    print_header "Step 2: Installation Confirmation"

    print_warn "⚠️  WARNING: This will install NixOS on $INDIA_STRONG_IP"
    print_warn "⚠️  WARNING: This WILL ERASE the disk!"
    print_warn "⚠️  WARNING: This is IRREVERSIBLE!"
    echo ""

    read -p "Do you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_info "Installation cancelled"
        exit 0
    fi

    read -p "Type the IP address to confirm ($INDIA_STRONG_IP): " ip_confirm
    if [ "$ip_confirm" != "$INDIA_STRONG_IP" ]; then
        print_error "IP address mismatch! Installation cancelled"
        exit 1
    fi

    echo ""
    print_info "Installation confirmed. Starting in 3 seconds..."
    sleep 3
    echo ""
}

# Run installation
run_installation() {
    print_header "Step 3: Running NixOS Installation"

    cd "$REPO_DIR"

    print_info "Starting nixos-anywhere..."
    print_info "This will take 10-15 minutes. Do NOT interrupt!"
    echo ""

    nix run github:nix-community/nixos-anywhere -- \
        --flake .#node-india-strong \
        --extra-files ./infra/nixos/secrets \
        -i "$SSH_KEY" \
        ubuntu@"$INDIA_STRONG_IP"

    echo ""
    print_info "✓ Installation script completed"
    echo ""
}

# Wait for system to boot
wait_for_boot() {
    print_header "Step 4: Waiting for System Boot"

    print_info "System is rebooting. Waiting 5 minutes for full boot..."

    for i in {300..1}; do
        remaining=$((i / 60))
        if [ $((i % 10)) -eq 0 ]; then
            print_info "Waiting... ${remaining}m remaining"
        fi
        sleep 1
    done

    echo ""
    print_info "✓ Boot wait period completed"
    echo ""
}

# Verify installation
verify_installation() {
    print_header "Step 5: Verifying NixOS Installation"

    print_step "Checking NixOS version"
    nixos_version=$(ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "nixos-rebuild --version" 2>/dev/null)
    print_info "NixOS version: $nixos_version"

    print_step "Checking hostname"
    hostname=$(ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "hostname" 2>/dev/null)
    print_info "Hostname: $hostname"

    print_step "Checking system info"
    uname=$(ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "uname -a" 2>/dev/null)
    print_info "System: $uname"

    print_step "Checking available disk"
    disk=$(ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "df -h" 2>/dev/null)
    print_info "Disk usage:"
    echo "$disk" | awk '{printf "  %s\n", $0}'

    print_step "Checking available memory"
    memory=$(ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "free -h" 2>/dev/null)
    print_info "Memory:"
    echo "$memory" | awk '{printf "  %s\n", $0}'

    echo ""
    print_info "✓ NixOS installation verified"
    echo ""
}

# Verify services
verify_services() {
    print_header "Step 6: Verifying Services"

    print_step "Checking PostgreSQL"
    if ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "sudo systemctl is-active postgresql" 2>/dev/null | grep -q "active"; then
        print_info "PostgreSQL: ✓ running"
    else
        print_warn "PostgreSQL: ✗ not running (may still be starting)"
    fi

    print_step "Checking Patroni"
    if ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "sudo systemctl is-active patroni" 2>/dev/null | grep -q "active"; then
        print_info "Patroni: ✓ running"
    else
        print_warn "Patroni: ✗ not running (may still be starting)"
    fi

    print_step "Checking etcd"
    if ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "sudo systemctl is-active etcd" 2>/dev/null | grep -q "active"; then
        print_info "etcd: ✓ running"
    else
        print_warn "etcd: ✗ not running (may still be starting)"
    fi

    print_step "Checking ClickHouse"
    if ssh -i "$SSH_KEY" root@"$INDIA_STRONG_IP" "sudo systemctl is-active clickhouse-server" 2>/dev/null | grep -q "active"; then
        print_info "ClickHouse: ✓ running"
    else
        print_warn "ClickHouse: ✗ not running (may still be starting)"
    fi

    echo ""
}

# Print summary
print_summary() {
    print_header "NixOS Installation Complete! ✅"

    echo ""
    echo "Installation Summary:"
    echo "  Server:  $INDIA_STRONG_IP"
    echo "  Region:  ap-south-1 (India Hyderabad)"
    echo "  OS:      NixOS 24.11"
    echo "  Arch:    ARM64 (aarch64)"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "  1. SSH to node:"
    echo "     ssh -i $SSH_KEY root@$INDIA_STRONG_IP"
    echo ""
    echo "  2. Check services (if not all running yet):"
    echo "     sudo systemctl status | grep -E 'postgresql|patroni|etcd|clickhouse'"
    echo ""
    echo "  3. Deploy application:"
    echo "     cd $REPO_DIR"
    echo "     colmena apply --on node-india-strong"
    echo ""
    echo "  4. Monitor logs:"
    echo "     ssh -i $SSH_KEY root@$INDIA_STRONG_IP"
    echo "     sudo journalctl -u uptrack-app -f"
    echo ""
    echo "Documentation:"
    echo "  - Installation guide: $REPO_DIR/NIXOS_INSTALLATION.md"
    echo "  - India Strong setup: $REPO_DIR/INDIA_STRONG_SETUP_SUMMARY.md"
    echo ""
}

# Main execution
main() {
    print_header "NixOS Installation for India Strong Node"

    verify_prerequisites
    confirm_installation
    run_installation
    wait_for_boot
    verify_installation
    verify_services
    print_summary
}

# Run main function
main "$@"
