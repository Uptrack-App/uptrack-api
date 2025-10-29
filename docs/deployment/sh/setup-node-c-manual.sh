#!/bin/bash

# Manual setup for Node C
# This will give you commands to copy/paste

NODE_IP="147.93.146.35"
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"

echo "🔧 Node C Setup Instructions"
echo "=============================="
echo ""
echo "1️⃣  First, SSH into the server (password: vietnam123):"
echo "   ssh root@$NODE_IP"
echo ""
echo "2️⃣  Once logged in, run these commands:"
echo ""
echo "# Create .ssh directory if it doesn't exist"
echo "mkdir -p ~/.ssh"
echo "chmod 700 ~/.ssh"
echo ""
echo "# Add your public key"
echo "echo '$PUBKEY' >> ~/.ssh/authorized_keys"
echo "chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "# Exit the server"
echo "exit"
echo ""
echo "3️⃣  Test SSH key login (should work without password):"
echo "   ssh root@$NODE_IP"
echo ""
echo "4️⃣  After SSH is working, run the main setup:"
echo "   ./setup-node-c.sh"
echo ""
