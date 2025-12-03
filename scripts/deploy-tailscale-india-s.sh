#!/usr/bin/env bash
# Deploy Tailscale to india-s (india-hyderabad-1)
# Run this script ON YOUR LOCAL MACHINE

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Deploying Tailscale to india-s (152.67.179.42) ===${NC}"
echo ""

# Auth key
AUTHKEY="REMOVED_TAILSCALE_AUTH_KEY"

# Step 1: Push code to remote node
echo -e "${YELLOW}Step 1: Syncing code to remote node...${NC}"
rsync -avz --exclude='.git' --exclude='result' --exclude='node_modules' \
  -e "ssh -i ~/.ssh/id_ed25519" \
  /Users/le/repos/uptrack/ \
  le@152.67.179.42:~/repos/uptrack/

echo -e "${GREEN}✓ Code synced${NC}"
echo ""

# Step 2: Remote deployment
echo -e "${YELLOW}Step 2: Running NixOS rebuild on remote node...${NC}"
echo ""

ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 << 'ENDSSH'
set -euo pipefail

cd ~/repos/uptrack

echo "=== Step 2a: Validate config (dry-build) ==="
sudo nixos-rebuild dry-build --flake '.#india-hyderabad-1'

echo ""
echo "=== Step 2b: Build config (15-20 min first time) ==="
sudo nixos-rebuild build --flake '.#india-hyderabad-1' --max-jobs 3

echo ""
echo "=== Step 2c: Switch to new config ==="
sudo TAILSCALE_AUTHKEY="REMOVED_TAILSCALE_AUTH_KEY" \
  nixos-rebuild switch --flake '.#india-hyderabad-1'

echo ""
echo "=== Waiting for Tailscale to connect ==="
sleep 5

echo ""
echo "=== Tailscale Status ==="
sudo tailscale status

echo ""
echo "=== Tailscale IP ==="
sudo tailscale ip -4
ENDSSH

echo ""
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Go to https://login.tailscale.com/admin/machines"
echo "2. Find machine 'india-s'"
echo "3. Edit IP address → Set to 100.64.1.10"
