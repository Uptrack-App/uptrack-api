#!/bin/bash
set -e

# Complete setup script for Node C (ClickHouse node)
NODE_C_IP="147.93.146.35"

echo "🚀 Setting up Node C (ClickHouse node)..."
echo "IP: $NODE_C_IP"
echo ""

# Check if we can SSH without password
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 root@$NODE_C_IP exit 2>/dev/null; then
    echo "❌ SSH key authentication not working. Run ./setup-ssh-expect.sh first"
    exit 1
fi

echo "✅ SSH connection verified"
echo ""

echo "📦 Step 1: Installing Tailscale..."
ssh root@$NODE_C_IP "curl -fsSL https://tailscale.com/install.sh | sh"

echo ""
echo "⚠️  IMPORTANT: Get your Tailscale auth key"
echo ""
echo "1. Go to: https://login.tailscale.com/admin/settings/keys"
echo "2. Click 'Generate auth key'"
echo "3. ✅ Enable 'Reusable' option"
echo "4. ✅ Set expiration to 90 days (or more)"
echo "5. Copy the key (starts with 'tskey-auth-...')"
echo ""
read -p "Paste your Tailscale auth key: " TAILSCALE_KEY

if [ -z "$TAILSCALE_KEY" ]; then
    echo "❌ No auth key provided"
    exit 1
fi

echo ""
echo "🔐 Step 2: Connecting to Tailscale network..."
ssh root@$NODE_C_IP "tailscale up --authkey=$TAILSCALE_KEY --accept-routes --hostname=uptrack-node-c"

echo ""
echo "📍 Step 3: Getting Tailscale IP..."
TAILSCALE_IP=$(ssh root@$NODE_C_IP "tailscale ip -4")
echo "✅ Tailscale IP: $TAILSCALE_IP"

echo ""
echo "🔑 Step 4: Getting SSH host key..."
SSH_HOST_KEY=$(ssh root@$NODE_C_IP "cat /etc/ssh/ssh_host_ed25519_key.pub")
echo "✅ SSH Host Key obtained"

echo ""
echo "======================================"
echo "✅ Node C Setup Complete!"
echo "======================================"
echo ""
echo "📋 Configuration Updates Needed:"
echo ""
echo "1️⃣  Update flake.nix (line ~80):"
echo "    targetHost = \"$NODE_C_IP\";"
echo ""
echo "2️⃣  Update Tailscale IP in these files (replace 100.64.0.3 with $TAILSCALE_IP):"
echo "    - infra/nixos/services/etcd.nix"
echo "    - infra/nixos/services/patroni.nix"
echo "    - infra/nixos/services/haproxy.nix"
echo "    - infra/nixos/services/uptrack-app.nix"
echo ""
echo "3️⃣  Add to infra/nixos/secrets/secrets.nix:"
echo "    node-c = \"$SSH_HOST_KEY\";"
echo ""
echo "4️⃣  Update Cloudflare DNS:"
echo "    Type: A"
echo "    Name: uptrack.app (or @)"
echo "    Content: $NODE_C_IP"
echo "    Proxy: ✅ Enabled (orange cloud)"
echo "    TTL: Auto"
echo ""
echo "🎯 Save this information:"
cat > /Users/le/repos/uptrack/node-c-info.txt << EOF
Node C Information
==================
Public IP: $NODE_C_IP
Tailscale IP: $TAILSCALE_IP
SSH Host Key: $SSH_HOST_KEY
Role: ClickHouse + Phoenix + etcd
Region: ap-southeast (or your chosen region)
EOF

echo "✅ Saved to: node-c-info.txt"
echo ""
echo "🔄 Next: Set up Node A and Node B, then run deployment!"
