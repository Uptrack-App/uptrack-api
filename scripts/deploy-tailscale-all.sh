#!/usr/bin/env bash
# DEPRECATED (2026-01-28): All nodes are now on NixOS with Tailscale managed via
# NixOS configuration (flake). This script was used for the initial Tailscale
# deployment to eu-a/b/c + india-rworker (Debian era). Kept for reference or
# re-deployment only. Current nodes: nbg1, nbg2, nbg3, nbg4, india-rworker.
#
# Original purpose: Deploy Tailscale to all 4 nodes
# Run from your local machine

set -euo pipefail

echo "This script is deprecated. All nodes now run NixOS with Tailscale managed in the flake."
echo "Current active nodes: nbg1 (100.64.1.1), nbg2 (100.64.1.2), nbg3 (100.64.1.3), nbg4 (100.64.1.4), india-rworker (100.64.1.11)"
echo "To re-deploy, review and update the node list below, then remove this exit guard."
exit 0

# --- Legacy script below (eu-a/b/c era, Debian-based) ---

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

AUTHKEY="tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg"

echo -e "${YELLOW}=== Deploying Tailscale to All 4 Nodes ===${NC}"
echo ""

# Test SSH connectivity first
echo -e "${YELLOW}Step 1: Testing SSH connectivity to all nodes...${NC}"
echo ""

NODES=(
  "eu-a:root@194.180.207.223"
  "eu-b:root@194.180.207.225"
  "eu-c:root@194.180.207.226"
  "india-rworker:root@144.24.150.48"
)

FAILED=0
for node in "${NODES[@]}"; do
  NAME="${node%%:*}"
  SSH="${node#*:}"

  echo -n "Testing $NAME ($SSH)... "

  if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $SSH "echo 'OK'" &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
  else
    echo -e "${RED}✗ FAILED${NC}"
    FAILED=1
  fi
done

if [ $FAILED -eq 1 ]; then
  echo ""
  echo -e "${RED}Some nodes are unreachable. Fix SSH access before continuing.${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}All nodes reachable!${NC}"
echo ""

# Deploy to each node
echo -e "${YELLOW}Step 2: Deploying Tailscale...${NC}"
echo ""

# Deploy to india-rworker
echo -e "${YELLOW}=== Deploying to india-rworker ===${NC}"
cat scripts/install-tailscale-debian.sh | ssh root@144.24.150.48 "bash -s india-rworker $AUTHKEY"
echo ""

# Deploy to eu-a
echo -e "${YELLOW}=== Deploying to eu-a ===${NC}"
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.223 "bash -s eu-a $AUTHKEY"
echo ""

# Deploy to eu-b
echo -e "${YELLOW}=== Deploying to eu-b ===${NC}"
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.225 "bash -s eu-b $AUTHKEY"
echo ""

# Deploy to eu-c
echo -e "${YELLOW}=== Deploying to eu-c ===${NC}"
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.226 "bash -s eu-c $AUTHKEY"
echo ""

echo -e "${GREEN}✓✓✓ All 4 nodes deployed! ✓✓✓${NC}"
echo ""
echo -e "${YELLOW}=== Next Steps ===${NC}"
echo "1. Go to: https://login.tailscale.com/admin/machines"
echo "2. You should see 4 machines online:"
echo "   - india-rworker"
echo "   - eu-a"
echo "   - eu-b"
echo "   - eu-c"
echo ""
echo "3. Assign static IPs to each machine:"
echo "   - india-rworker  → 100.64.1.11"
echo "   - eu-a     → 100.64.1.1"
echo "   - eu-b     → 100.64.1.2"
echo "   - eu-c     → 100.64.1.3"
echo ""
echo "4. Verify connectivity:"
echo "   ping -c 3 100.64.1.1   # eu-a"
echo "   ping -c 3 100.64.1.2   # eu-b"
echo "   ping -c 3 100.64.1.3   # eu-c"
echo "   ping -c 3 100.64.1.11  # india-rworker"
