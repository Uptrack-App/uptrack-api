# NixOS Installation for India Strong Node

## Prerequisites Checklist

Before running the installation, verify:

- [ ] SSH connectivity works: `ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171`
- [ ] SSH key permissions are 600: `ls -la ~/.ssh/ssh-key-2025-10-18.key` shows `-rw-------`
- [ ] Flake configuration exists: `/Users/le/repos/uptrack/flake.nix`
- [ ] Node configuration exists: `/Users/le/repos/uptrack/infra/nixos/node-india-strong.nix`
- [ ] You have ~20 GB free disk space on the instance
- [ ] You have stable internet connection (installation takes 10-15 minutes)

---

## What nixos-anywhere Does

```
1. Connects to the instance as root (via SSH)
2. Downloads NixOS 24.11 ARM64 image
3. Partitions the disk using disko configuration
4. Installs NixOS base system
5. Applies all node configurations (PostgreSQL, etcd, app, etc.)
6. Reboots the system
7. Returns to your MacBook when done
```

---

## Step 1: Prepare Your Machine

### Set Environment Variables

```bash
cd /Users/le/repos/uptrack

export INDIA_STRONG_IP="144.24.133.171"
export SSH_KEY="/Users/le/.ssh/ssh-key-2025-10-18.key"
```

### Verify SSH Key Permissions

```bash
chmod 600 $SSH_KEY
ls -la $SSH_KEY
# Should show: -rw------- (600 permissions)
```

---

## Step 2: Run nixos-anywhere Installation

### Command

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i $SSH_KEY \
  ubuntu@$INDIA_STRONG_IP
```

### What You'll See

**Initial Output:**
```
[INFO] Connecting to root@144.24.133.171...
[INFO] Uploading NixOS configuration...
[INFO] Downloading NixOS 24.11 ARM64 image...
[INFO] Partitioning disk...
```

**Progress (takes 10-15 minutes):**
- Image download: ~2-3 min (slow internet possible)
- Installation: ~5-10 min
- Configuration application: ~2-3 min

**Final Output:**
```
[INFO] Installation complete!
[INFO] System will reboot now...
```

---

## Step 3: Wait for System to Boot

After the script completes:

1. **Do NOT interrupt** - Let the system reboot
2. **Wait 5 minutes** - For NixOS to fully boot
3. **System will be unavailable** during this time

```bash
# You can check progress after 5 minutes with:
ping 144.24.133.171

# Once responsive, try SSH:
ssh -i $SSH_KEY root@144.24.133.171
```

---

## Step 4: Verify NixOS Installation

After the system reboots, verify NixOS is running:

```bash
# SSH to the node
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Check NixOS version
nixos-rebuild --version
# Should show: NixOS 25.05

# Check hostname
hostname
# Should show: uptrack-node-india-strong

# Check system info
uname -a
# Should show: Linux uptrack-node-india-strong ... aarch64 GNU/Linux

# Check available disk
df -h
# Should show mounted partitions from Oracle block volumes

# Check system resources
free -h
# Should show ~24 GB RAM

# Check CPU
lscpu | grep -E "CPU|cores"
# Should show ARM64 CPU details
```

---

## Step 5: Verify Services Are Running

```bash
# SSH to node
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Check all services
sudo systemctl status | grep -E "postgresql|patroni|etcd|clickhouse|uptrack"

# Check specific services
sudo systemctl status postgresql
sudo systemctl status patroni
sudo systemctl status etcd
sudo systemctl status clickhouse-server
sudo systemctl status uptrack-app

# Check logs
sudo journalctl -u postgresql -n 20
sudo journalctl -u patroni -n 20
sudo journalctl -u etcd -n 20
```

---

## Step 6: Deploy Application Configuration with Colmena

After NixOS installation completes and services are running:

```bash
cd /Users/le/repos/uptrack

# Deploy only to India Strong
colmena apply --on node-india-strong

# Or deploy to all nodes
colmena apply --all
```

This will:
- ✅ Build Phoenix release
- ✅ Deploy to India Strong node
- ✅ Configure environment variables
- ✅ Start/restart services

---

## Troubleshooting

### Issue 1: nixos-anywhere Command Not Found

**Error:**
```
command not found: nix run
```

**Solution:**
- Ensure Nix is installed: `nix --version`
- If not installed, install Nix from: https://nixos.org/download.html

### Issue 2: SSH Timeout During Installation

**Error:**
```
ssh: connect to host 144.24.133.171 port 22: Operation timed out
```

**Solution:**
- Verify SSH works before starting: `ssh -i $SSH_KEY ubuntu@144.24.133.171`
- Check network connectivity: `ping 144.24.133.171`
- Wait 1-2 minutes and retry (system might be rebooting)

### Issue 3: Disk Partition Error

**Error:**
```
[ERROR] Disk partitioning failed
```

**Possible Solutions:**
1. Check available disk: `df -h` before installation
2. Ensure no other volumes are mounted
3. Try installation again (might be transient)

### Issue 4: System Doesn't Boot After Installation

**Symptoms:**
- Can't SSH to node after installation completes
- Ping times out

**Solutions:**
1. Wait 5-10 minutes for system to fully boot
2. Check Oracle Console for instance status
3. Try reboot from Oracle Console: **Compute → Instances → Reboot**
4. Check boot logs: **Instance Details → Boot Volume → View Logs**

### Issue 5: Services Not Running

**Check:**
```bash
sudo systemctl status postgresql
sudo systemctl status patroni

# Check logs for errors
sudo journalctl -u postgresql -n 50
sudo journalctl -u patroni -n 50
```

**Common Issues:**
- PostgreSQL port (5432) not accessible
- Patroni configuration incorrect
- etcd not joining cluster

---

## Full Step-by-Step Script

Here's everything in one go:

```bash
#!/bin/bash
set -e

echo "🚀 NixOS Installation for India Strong Node"
echo ""

# Configuration
export INDIA_STRONG_IP="144.24.133.171"
export SSH_KEY="/Users/le/.ssh/ssh-key-2025-10-18.key"

# Change to repo directory
cd /Users/le/repos/uptrack

echo "1️⃣  Verifying prerequisites..."
echo "   SSH key permissions..."
chmod 600 $SSH_KEY

echo "   Testing SSH connectivity..."
ssh -i $SSH_KEY -o ConnectTimeout=5 ubuntu@$INDIA_STRONG_IP "echo 'SSH works ✓'"

echo ""
echo "2️⃣  Running nixos-anywhere installation..."
echo "   This will take 10-15 minutes..."
echo "   Do NOT interrupt!"
echo ""

nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i $SSH_KEY \
  ubuntu@$INDIA_STRONG_IP

echo ""
echo "3️⃣  Installation complete!"
echo "   System is rebooting..."
echo "   Waiting 5 minutes for system to boot..."
sleep 300

echo ""
echo "4️⃣  Verifying NixOS installation..."
ssh -i $SSH_KEY root@$INDIA_STRONG_IP "nixos-rebuild --version"
ssh -i $SSH_KEY root@$INDIA_STRONG_IP "hostname"

echo ""
echo "✅ NixOS Installation Successful!"
echo ""
echo "Next steps:"
echo "1. Verify services: ssh -i $SSH_KEY root@$INDIA_STRONG_IP"
echo "2. Deploy apps:    colmena apply --on node-india-strong"
echo "3. Check logs:     ssh -i $SSH_KEY root@$INDIA_STRONG_IP journalctl -f"
```

---

## After Successful Installation

### Verify Cluster Status

```bash
# Check PostgreSQL replication
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "psql -U postgres -c \"SELECT NOW(), pg_last_wal_receive_lsn();\""

# Check Patroni cluster
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "patronictl list uptrack-pg-cluster"

# Check etcd cluster
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "etcdctl endpoint health --cluster"
```

### Monitor Logs

```bash
# Watch PostgreSQL logs
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "sudo journalctl -u postgresql -f"

# Watch Patroni logs
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "sudo journalctl -u patroni -f"

# Watch application logs
ssh -i $SSH_KEY root@$INDIA_STRONG_IP \
  "sudo journalctl -u uptrack-app -f"
```

---

## Quick Commands Reference

```bash
# SSH to node
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Check services
sudo systemctl status | grep uptrack

# Restart a service
sudo systemctl restart postgresql
sudo systemctl restart patroni
sudo systemctl restart uptrack-app

# View logs
sudo journalctl -u postgresql -n 50
sudo journalctl -u uptrack-app -f

# Reboot node
sudo reboot

# Check NixOS generation
sudo nixos-rebuild list-generations
```

---

## Important Notes

1. **ARM64 Architecture**: India Strong uses ARM64 - all binaries must be compatible
2. **Building on Target**: `buildOnTarget = true` in flake.nix - builds happen on the server
3. **Slow Internet**: Expect slower download/build times in India region
4. **Patroni Replication**: Will join the cluster after booting
5. **etcd Cluster**: Will join the existing etcd cluster

---

**Status**: Ready for NixOS installation
**Last Updated**: 2025-10-19
**Estimated Time**: 15-20 minutes
