#!/bin/bash
set -e

# Setup script for Node C (ClickHouse + Phoenix)
# Run this on your local machine

NODE_C_IP="147.93.146.35"
NODE_C_PASSWORD="REMOVED_PASSWORD"

echo "🚀 Setting up Node C (ClickHouse node)..."
echo "IP: $NODE_C_IP"
echo ""

# Function to run commands via SSH
run_ssh() {
    sshpass -p "$NODE_C_PASSWORD" ssh -o StrictHostKeyChecking=no root@$NODE_C_IP "$1"
}

# Function to copy files via SCP
copy_file() {
    sshpass -p "$NODE_C_PASSWORD" scp -o StrictHostKeyChecking=no "$1" root@$NODE_C_IP:"$2"
}

echo "📦 Step 1: Installing Tailscale..."
run_ssh "curl -fsSL https://tailscale.com/install.sh | sh"

echo ""
echo "⚠️  IMPORTANT: You need to get a Tailscale auth key first!"
echo "1. Go to: https://login.tailscale.com/admin/settings/keys"
echo "2. Click 'Generate auth key'"
echo "3. Enable 'Reusable' option"
echo "4. Copy the key"
echo ""
read -p "Paste your Tailscale auth key: " TAILSCALE_KEY

echo ""
echo "🔐 Step 2: Connecting to Tailscale network..."
run_ssh "tailscale up --authkey=$TAILSCALE_KEY --accept-routes"

echo ""
echo "📍 Step 3: Getting Tailscale IP..."
TAILSCALE_IP=$(run_ssh "tailscale ip -4")
echo "Tailscale IP: $TAILSCALE_IP"

echo ""
echo "🔑 Step 4: Getting SSH host key..."
SSH_HOST_KEY=$(run_ssh "cat /etc/ssh/ssh_host_ed25519_key.pub")
echo "SSH Host Key: $SSH_HOST_KEY"

echo ""
echo "✅ Node C setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Update flake.nix line ~80:"
echo "   targetHost = \"$NODE_C_IP\";"
echo ""
echo "2. Update these files with Tailscale IP $TAILSCALE_IP:"
echo "   - infra/nixos/services/etcd.nix (nodeCTailscaleIP)"
echo "   - infra/nixos/services/patroni.nix (nodeCTailscaleIP)"
echo "   - infra/nixos/services/haproxy.nix (nodeCTailscaleIP)"
echo "   - infra/nixos/services/uptrack-app.nix (nodeCTailscaleIP)"
echo ""
echo "3. Add to infra/nixos/secrets/secrets.nix:"
echo "   node-c = \"$SSH_HOST_KEY\";"
echo ""
echo "4. Update Cloudflare DNS:"
echo "   Add A record: uptrack.app → $NODE_C_IP (Proxied)"
echo ""
echo "Run this script again for Node A and Node B!"
