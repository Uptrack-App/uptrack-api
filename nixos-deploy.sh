#!/usr/bin/env bash
# Uptrack NixOS Deployment Helper Script

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat << HELP
Uptrack NixOS Deployment Helper

Usage: ./nixos-deploy.sh <command>

Installation Commands:
    install-node-a      Install NixOS on Node A (Hetzner) - WIPES DISK!
    install-node-b      Install NixOS on Node B (Contabo) - WIPES DISK!
    install-node-c      Install NixOS on Node C (Contabo) - WIPES DISK!

Deployment Commands:
    deploy-all          Deploy to all nodes
    deploy-node-a       Deploy to Node A only
    deploy-node-b       Deploy to Node B only
    deploy-node-c       Deploy to Node C only

Utility Commands:
    build              Build configuration without deploying
    check              Check flake and run tests
    rekey              Re-encrypt all secrets after adding new keys

Node Management:
    ssh-node-a         SSH into Node A
    ssh-node-b         SSH into Node B
    ssh-node-c         SSH into Node C
    logs-node-a        View logs from Node A
    logs-node-b        View logs from Node B
    logs-node-c        View logs from Node C
    status-node-a      Check service status on Node A
    status-node-b      Check service status on Node B
    status-node-c      Check service status on Node C

Setup Commands:
    setup-secrets      Interactive setup for secrets
    generate-keys      Generate random secrets

Examples:
    ./nixos-deploy.sh install-node-c   # Initial installation
    ./nixos-deploy.sh deploy-all       # Deploy updates to all nodes
    ./nixos-deploy.sh logs-node-a      # View logs
HELP
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_nix() {
    if ! command -v nix &> /dev/null; then
        log_error "Nix is not installed. Please install Nix first:"
        echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
        exit 1
    fi
}

# Installation commands
install_node_a() {
    log_warn "This will WIPE Node A (91.98.89.119) and install NixOS!"
    read -p "Are you sure? Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Aborted."
        exit 0
    fi

    log_info "Installing NixOS on Node A..."
    nix run .#install-node-a
    log_info "Installation complete! Server should be rebooting."
    log_info "After reboot, add server SSH host key to secrets/secrets.nix and rekey."
}

install_node_b() {
    log_warn "This will WIPE Node B (185.237.12.64) and install NixOS!"
    read -p "Are you sure? Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Aborted."
        exit 0
    fi

    log_info "Installing NixOS on Node B..."
    nix run .#install-node-b
    log_info "Installation complete! Server should be rebooting."
    log_info "After reboot, add server SSH host key to secrets/secrets.nix and rekey."
}

install_node_c() {
    log_warn "This will WIPE Node C (147.93.146.35) and install NixOS!"
    read -p "Are you sure? Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Aborted."
        exit 0
    fi

    log_info "Installing NixOS on Node C..."
    nix run .#install-node-c
    log_info "Installation complete! Server should be rebooting."
    log_info "After reboot, add server SSH host key to secrets/secrets.nix and rekey."
}

# Deployment commands
deploy_all() {
    log_info "Deploying to all nodes..."
    nix run .#deploy-all
    log_info "Deployment complete!"
}

deploy_node_a() {
    log_info "Deploying to Node A..."
    nix run .#deploy-node-a
    log_info "Deployment complete!"
}

deploy_node_b() {
    log_info "Deploying to Node B..."
    nix run .#deploy-node-b
    log_info "Deployment complete!"
}

deploy_node_c() {
    log_info "Deploying to Node C..."
    nix run .#deploy-node-c
    log_info "Deployment complete!"
}

# Utility commands
build_config() {
    log_info "Building configuration..."
    nix develop --command colmena build
}

check_flake() {
    log_info "Checking flake..."
    nix flake check
    log_info "Flake check passed!"
}

rekey_secrets() {
    log_info "Re-encrypting secrets..."
    nix develop --command agenix --rekey
    log_info "Secrets re-encrypted!"
}

# Node management commands
ssh_node_a() {
    log_info "Connecting to Node A..."
    ssh root@91.98.89.119
}

ssh_node_b() {
    log_info "Connecting to Node B..."
    ssh root@185.237.12.64
}

ssh_node_c() {
    log_info "Connecting to Node C..."
    ssh root@147.93.146.35
}

logs_node_a() {
    log_info "Viewing logs from Node A (Ctrl+C to exit)..."
    ssh root@91.98.89.119 'journalctl -f -u uptrack-app -u postgresql -u timescaledb -u clickhouse-server -u haproxy'
}

logs_node_b() {
    log_info "Viewing logs from Node B (Ctrl+C to exit)..."
    ssh root@185.237.12.64 'journalctl -f -u uptrack-app -u postgresql -u timescaledb -u clickhouse-server'
}

logs_node_c() {
    log_info "Viewing logs from Node C (Ctrl+C to exit)..."
    ssh root@147.93.146.35 'journalctl -f -u uptrack-app -u postgresql -u timescaledb -u clickhouse-server'
}

status_node_a() {
    log_info "Checking service status on Node A..."
    ssh root@91.98.89.119 << 'SSHEOF'
        echo "=== Uptrack App ==="
        systemctl status uptrack-app --no-pager | head -10
        echo ""
        echo "=== PostgreSQL ==="
        systemctl status postgresql --no-pager | head -10
        echo ""
        echo "=== HAProxy ==="
        systemctl status haproxy --no-pager | head -10
SSHEOF
}

status_node_b() {
    log_info "Checking service status on Node B..."
    ssh root@185.237.12.64 << 'SSHEOF'
        echo "=== Uptrack App ==="
        systemctl status uptrack-app --no-pager | head -10
        echo ""
        echo "=== PostgreSQL ==="
        systemctl status postgresql --no-pager | head -10
SSHEOF
}

status_node_c() {
    log_info "Checking service status on Node C..."
    ssh root@147.93.146.35 << 'SSHEOF'
        echo "=== Uptrack App ==="
        systemctl status uptrack-app --no-pager | head -10
        echo ""
        echo "=== PostgreSQL ==="
        systemctl status postgresql --no-pager | head -10
SSHEOF
}

# Setup commands
setup_secrets() {
    log_info "Interactive secrets setup..."

    cd infra/nixos/secrets

    if [[ ! -f uptrack-env ]]; then
        cp uptrack-env.example uptrack-env
        log_info "Created uptrack-env from example"
    fi

    log_info "Please edit the following file and add real values:"
    echo "  - infra/nixos/secrets/uptrack-env"
    echo ""
    log_info "Then run: ./nixos-deploy.sh rekey"
}

generate_keys() {
    log_info "Generating random secrets..."
    echo ""
    echo "SECRET_KEY_BASE (64 chars):"
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-64
    echo ""
    echo "DB_PASSWORD (25 chars):"
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
    echo ""
    echo "LIVE_VIEW_SIGNING_SALT (32 chars):"
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
    echo ""
    echo "Generic secret (hex):"
    openssl rand -hex 32
    echo ""
}

main() {
    check_nix

    case "${1:-}" in
        install-node-a)
            install_node_a
            ;;
        install-node-b)
            install_node_b
            ;;
        install-node-c)
            install_node_c
            ;;
        deploy-all)
            deploy_all
            ;;
        deploy-node-a)
            deploy_node_a
            ;;
        deploy-node-b)
            deploy_node_b
            ;;
        deploy-node-c)
            deploy_node_c
            ;;
        build)
            build_config
            ;;
        check)
            check_flake
            ;;
        rekey)
            rekey_secrets
            ;;
        ssh-node-a)
            ssh_node_a
            ;;
        ssh-node-b)
            ssh_node_b
            ;;
        ssh-node-c)
            ssh_node_c
            ;;
        logs-node-a)
            logs_node_a
            ;;
        logs-node-b)
            logs_node_b
            ;;
        logs-node-c)
            logs_node_c
            ;;
        status-node-a)
            status_node_a
            ;;
        status-node-b)
            status_node_b
            ;;
        status-node-c)
            status_node_c
            ;;
        setup-secrets)
            setup_secrets
            ;;
        generate-keys)
            generate_keys
            ;;
        help|--help|-h)
            print_help
            ;;
        *)
            print_help
            exit 1
            ;;
    esac
}

main "$@"
