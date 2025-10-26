#!/bin/bash
# Setup root SSH access on Oracle Cloud instance
# Run this on your local machine

set -e

# Configuration
HOST="REMOVED_IP"
USER="ubuntu"
SSH_KEY="~/.ssh/id_ed25519"

echo "🔧 Setting up root SSH access on $HOST..."

# SSH as ubuntu and configure root access
ssh -i "$SSH_KEY" "$USER@$HOST" << 'ENDSSH'
set -e

echo "📋 Switching to root..."
sudo -i << 'ENDROOT'
set -e

echo "🔑 Setting up root SSH access..."

# Create .ssh directory for root
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Copy authorized_keys from ubuntu user
cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Enable root login in sshd_config
if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
else
    echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config
fi

# Restart SSH service
systemctl restart sshd

echo "✅ Root SSH access configured!"
echo "🔑 Root authorized_keys:"
cat /root/.ssh/authorized_keys

ENDROOT

ENDSSH

echo ""
echo "✅ Root SSH setup complete!"
echo ""
echo "🧪 Testing root SSH access..."
if ssh -i "$SSH_KEY" -o ConnectTimeout=5 root@"$HOST" "echo '✅ Root SSH access working!'" 2>/dev/null; then
    echo "✅ SUCCESS! You can now SSH as root:"
    echo "   ssh -i $SSH_KEY root@$HOST"
else
    echo "⚠️  Could not verify root access. Please try manually:"
    echo "   ssh -i $SSH_KEY root@$HOST"
fi
