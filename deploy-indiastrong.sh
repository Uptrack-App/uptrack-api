#!/usr/bin/env bash
# Deploy Uptrack with Idle Prevention to indiastrong node
# This script deploys the application to 152.67.179.42

set -e

echo "=== Deploying Uptrack to indiastrong ==="
echo "Target: 152.67.179.42"
echo "User: le"
echo ""

# Configuration
SSH_KEY="$HOME/.ssh/id_ed25519"
TARGET_HOST="152.67.179.42"
TARGET_USER="le"
REPO_URL="git@github.com:hoangbits/uptrack.git"
DEPLOY_DIR="/home/le/uptrack"

echo "[1/6] Testing SSH connection..."
ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" "echo 'Connected to indiastrong'"

echo ""
echo "[2/6] Cloning/updating repository..."
ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" bash <<'ENDSSH'
if [ -d "$HOME/uptrack" ]; then
  echo "Repository exists, pulling latest changes..."
  cd $HOME/uptrack
  git pull origin main
else
  echo "Cloning repository..."
  cd $HOME
  git clone https://github.com/hoangbits/uptrack.git
  cd uptrack
fi

echo "Current commit:"
git log --oneline -1
ENDSSH

echo ""
echo "[3/6] Installing Nix packages (if needed)..."
ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" bash <<'ENDSSH'
# Check if development tools are available
if ! command -v elixir &> /dev/null; then
  echo "Installing Elixir and dependencies via nix-shell..."
  cd $HOME/uptrack
  nix-shell --run "elixir --version" || echo "Nix shell configured"
else
  echo "Elixir already available"
fi
ENDSSH

echo ""
echo "[4/6] Checking if we can build the NixOS configuration..."
ssh -i "$SSH_KEY" "$TARGET_USER@$TARGET_HOST" bash <<'ENDSSH'
cd $HOME/uptrack
echo "Checking NixOS configuration..."
if [ -f "infra/nixos/node-india-strong.nix" ]; then
  echo "✓ Node configuration found"
else
  echo "✗ Node configuration not found!"
  exit 1
fi
ENDSSH

echo ""
echo "[5/6] Instructions for manual NixOS rebuild..."
echo ""
echo "The uptrack repository is now on indiastrong at: /home/le/uptrack"
echo ""
echo "To complete the deployment, run these commands ON THE SERVER:"
echo ""
echo "  ssh -i ~/.ssh/id_ed25519 le@152.67.179.42"
echo "  cd /home/le/uptrack"
echo "  sudo nixos-rebuild switch --flake .#node-india-strong"
echo ""
echo "OR, if you want to just run the Elixir app without full NixOS rebuild:"
echo ""
echo "  ssh -i ~/.ssh/id_ed25519 le@152.67.179.42"
echo "  cd /home/le/uptrack"
echo "  nix develop"
echo "  mix deps.get"
echo "  mix compile"
echo "  MIX_ENV=prod mix phx.server"
echo ""

echo "[6/6] Deployment preparation complete!"
echo ""
echo "Next steps:"
echo "1. SSH into the server"
echo "2. Choose deployment method (NixOS rebuild or direct Elixir)"
echo "3. Verify idle prevention is running"
echo ""
