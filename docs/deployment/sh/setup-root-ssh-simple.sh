#!/bin/bash
# Simple root SSH setup - run each command separately

HOST="REMOVED_IP"

echo "Step 1: Copy SSH key to root"
ssh -i ~/.ssh/id_ed25519 -t ubuntu@$HOST 'sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh && sudo cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys && sudo chmod 600 /root/.ssh/authorized_keys'

echo ""
echo "Step 2: Enable root login"
ssh -i ~/.ssh/id_ed25519 -t ubuntu@$HOST 'sudo bash -c "grep -q \"^PermitRootLogin\" /etc/ssh/sshd_config && sed -i \"s/^.*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config || echo \"PermitRootLogin prohibit-password\" >> /etc/ssh/sshd_config"'

echo ""
echo "Step 3: Restart SSH"
ssh -i ~/.ssh/id_ed25519 -t ubuntu@$HOST 'sudo systemctl restart sshd'

echo ""
echo "Step 4: Test root access"
sleep 2
ssh -i ~/.ssh/id_ed25519 root@$HOST 'echo "✅ Root SSH works!"'
