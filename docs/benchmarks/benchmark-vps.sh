#!/usr/bin/env bash
# VPS Performance Benchmark Script (using YABS)
# Usage: ./benchmark-vps.sh <hostname_or_ip> [ssh_user] [ssh_key_path] [options]
#
# This script runs YABS (Yet Another Bench Script) on a remote VPS.
# YABS is the industry standard for VPS benchmarking.
# https://github.com/masonr/yet-another-bench-script
#
# Examples:
#   ./benchmark-vps.sh 34.130.208.111 jd ~/.ssh/id_ed25519_spc
#   ./benchmark-vps.sh REMOVED_IP root ~/.ssh/id_ed25519
#   ./benchmark-vps.sh REMOVED_IP root ~/.ssh/id_ed25519 quick    # Skip Geekbench
#   ./benchmark-vps.sh REMOVED_IP root ~/.ssh/id_ed25519 full     # Full benchmark

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

HOST="${1:-}"
SSH_USER="${2:-root}"
SSH_KEY="${3:-$HOME/.ssh/id_ed25519}"
MODE="${4:-quick}"  # quick, full, disk-only, network-only

if [ -z "$HOST" ]; then
    echo -e "${RED}Error: No hostname provided${NC}"
    echo ""
    echo "Usage: $0 <hostname_or_ip> [ssh_user] [ssh_key_path] [mode]"
    echo ""
    echo "Modes:"
    echo "  quick       - Skip Geekbench (faster, ~2-3 min)"
    echo "  full        - Full benchmark including Geekbench (~10-15 min)"
    echo "  disk-only   - Only disk tests"
    echo "  network-only - Only network tests"
    echo ""
    echo "Examples:"
    echo "  $0 34.130.208.111 jd ~/.ssh/id_ed25519_spc"
    echo "  $0 REMOVED_IP root ~/.ssh/id_ed25519 quick"
    echo "  $0 REMOVED_IP root ~/.ssh/id_ed25519 full"
    exit 1
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       VPS Performance Benchmark (YABS)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Target:${NC} $SSH_USER@$HOST"
echo -e "${CYAN}Date:${NC} $(date)"
echo -e "${CYAN}Mode:${NC} $MODE"
echo -e "${CYAN}SSH Key:${NC} $SSH_KEY"
echo ""

# Test SSH connectivity
echo -e "${YELLOW}[1/3] Testing SSH connectivity...${NC}"
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$HOST" "echo 'SSH OK'" &>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    exit 1
fi

# Function to run remote command
run_remote() {
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$HOST" "$@"
}

# Get system info first
echo ""
echo -e "${YELLOW}[2/3] Gathering system information...${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"

echo -e "\n${CYAN}=== CPU ===${NC}"
run_remote "cat /proc/cpuinfo | grep 'model name' | head -1 || echo 'Unknown CPU'"
run_remote "lscpu | grep -E 'CPU\(s\)|Architecture' | head -2"

echo -e "\n${CYAN}=== Memory ===${NC}"
run_remote "free -h | grep -E '^Mem:'"

echo -e "\n${CYAN}=== Disk ===${NC}"
run_remote "df -h / | tail -1"

echo -e "\n${CYAN}=== OS ===${NC}"
run_remote "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2"

# Build YABS options based on mode
echo ""
echo -e "${YELLOW}[3/3] Running YABS benchmark...${NC}"
echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"

case "$MODE" in
    "quick")
        echo -e "${CYAN}Mode: Quick (skipping Geekbench for faster results)${NC}"
        YABS_OPTS="-g"  # Skip Geekbench
        ;;
    "full")
        echo -e "${CYAN}Mode: Full benchmark (including Geekbench, ~10-15 min)${NC}"
        YABS_OPTS=""
        ;;
    "disk-only")
        echo -e "${CYAN}Mode: Disk-only (fio tests)${NC}"
        YABS_OPTS="-i -g"  # Skip iperf and Geekbench
        ;;
    "network-only")
        echo -e "${CYAN}Mode: Network-only (iperf3 tests)${NC}"
        YABS_OPTS="-f -g"  # Skip fio and Geekbench
        ;;
    *)
        echo -e "${YELLOW}Unknown mode '$MODE', using quick mode${NC}"
        YABS_OPTS="-g"
        ;;
esac

echo ""
echo -e "${GREEN}Running YABS on $HOST...${NC}"
echo -e "${YELLOW}This may take 2-15 minutes depending on mode.${NC}"
echo ""

# Run YABS
run_remote "curl -sL yabs.sh | bash -s -- $YABS_OPTS"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}              Reference: Other Providers${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "┌──────────────────┬────────────┬────────────┬──────────┬──────────┐"
echo -e "│ ${CYAN}Provider${NC}         │ ${CYAN}CPU (ev/s)${NC} │ ${CYAN}Disk Write${NC} │ ${CYAN}Disk Read${NC}│ ${CYAN}Price${NC}    │"
echo -e "├──────────────────┼────────────┼────────────┼──────────┼──────────┤"
echo -e "│ GCP e2-standard-2│    1330    │   175 MB/s │  183 MB/s│ ~\$55/mo  │"
echo -e "│ Hetzner ARM64    │   ~1038    │  1400 MB/s │  2.0 GB/s│  €8/mo   │"
echo -e "│ Hostkey Italy    │     940    │   827 MB/s │  1.8 GB/s│ €4.17/mo │"
echo -e "│ Oracle ARM64     │    ~900    │  ~200 MB/s │ ~300 MB/s│   FREE   │"
echo -e "│ Contabo          │    ~365    │   173 MB/s │  444 MB/s│  €6/mo   │"
echo -e "└──────────────────┴────────────┴────────────┴──────────┴──────────┘"
echo ""
echo -e "${CYAN}Note:${NC} YABS uses fio for disk tests (more accurate than dd)."
echo -e "${CYAN}      Compare fio results above with these reference values.${NC}"
echo ""

echo -e "${GREEN}Benchmark complete!${NC}"
echo -e "Report generated: $(date)"
echo ""
