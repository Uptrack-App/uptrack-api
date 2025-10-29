#!/bin/bash
set -e

# Install NixOS on Node C using nixos-anywhere
NODE_C_IP="147.93.146.35"
NODE_NAME="node-c"

echo "🚀 Installing NixOS on Node C (ClickHouse node)"
echo "IP: $NODE_C_IP"
echo ""
echo "⚠️  WARNING: This will WIPE the server and install NixOS!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Installation cancelled"
    exit 1
fi

echo ""
echo "📦 Installing NixOS with nixos-anywhere..."
echo "You will be prompted for the root password: REMOVED_PASSWORD"
echo ""

# Run nixos-anywhere
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-c \
  root@$NODE_C_IP

echo ""
echo "✅ NixOS installation complete!"
echo ""
echo "🔍 Verifying installation..."

# Wait a bit for the system to fully boot
echo "Waiting 30 seconds for system to stabilize..."
sleep 30

# Test SSH connection
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$NODE_C_IP "echo 'SSH working!'"; then
    echo "✅ SSH connection verified"
else
    echo "⚠️  SSH connection failed - server may still be rebooting"
    echo "Try: ssh root@$NODE_C_IP"
fi

echo ""
echo "📝 Next steps:"
echo "1. Get Tailscale auth key from: https://login.tailscale.com/admin/settings/keys"
echo "2. SSH into the server: ssh root@$NODE_C_IP"
echo "3. Connect to Tailscale: tailscale up --authkey=YOUR_KEY --hostname=uptrack-node-c"
echo "4. Get Tailscale IP: tailscale ip -4"
echo "5. Update config files with the Tailscale IP"
echo "6. Deploy the configuration: colmena apply --on node-c"
echo ""
