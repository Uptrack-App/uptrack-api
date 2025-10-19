# NixOS Installation Guide for India Strong Node

## Issue Summary

**Current Status**: ❌ Cannot reach India Strong (144.24.133.171) over SSH

**Root Cause**: Network connectivity issue - 100% packet loss to the IP address

**Next Step**: You need to verify the instance is running in Oracle Cloud Console

---

## Prerequisites Checklist

Before proceeding, verify in **Oracle Cloud Console**:

- [ ] Instance **uptrack-node-india-strong** exists
- [ ] Instance state is **RUNNING** (not STOPPED)
- [ ] Public IPv4 address is `144.24.133.171` (or update if different)
- [ ] Security rules allow SSH port 22 inbound
- [ ] SSH key `ssh-key-2025-10-18.key` is authorized on the instance

---

## Step 1: Verify Instance is Running

### In Oracle Cloud Console:

1. Go to **Compute → Instances**
2. Find your instance
3. Verify state shows **RUNNING**
4. Copy the **Public IPv4 Address** (should be `144.24.133.171`)

If instance is **STOPPED**, click the "Start" button and wait 2-3 minutes.

---

## Step 2: Test SSH Connection

Once instance is running, verify connectivity:

```bash
# Test ping
ping -c 3 144.24.133.171

# Should see responses (not timeouts)
# PING 144.24.133.171 (144.24.133.171): 56 data bytes
# 64 bytes from 144.24.133.171: icmp_seq=0 ttl=50 time=150.000 ms
```

If ping works, try SSH:

```bash
# Test SSH
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Should prompt for Ubuntu shell or ask for password
```

**If this fails, see**: `INDIA_STRONG_DEBUG.md`

---

## Step 3: Prepare for NixOS Installation

Once SSH is working as `ubuntu` user:

```bash
# Connect to instance
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Become root (you'll need to enter password or use sudo)
sudo su -

# Verify system info
uname -a
# Should show: Linux ... aarch64 GNU/Linux

# Check available disk
lsblk
# Should show boot device (e.g., /dev/sda) and any additional volumes
```

---

## Step 4: Install NixOS with nixos-anywhere

### From your MacBook (NOT on the server):

```bash
cd /Users/le/repos/uptrack

# Set variables
export INDIA_STRONG_IP="144.24.133.171"
export SSH_KEY="/Users/le/.ssh/ssh-key-2025-10-18.key"

# Fix SSH key permissions
chmod 400 $SSH_KEY

# Run nixos-anywhere to install NixOS
# This will:
# - Download NixOS ARM64 image
# - Partition the disk using disko configuration
# - Install NixOS base system
# - Apply node configurations
# - Takes 10-15 minutes

nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i $SSH_KEY \
  root@$INDIA_STRONG_IP
```

**What to expect:**
- Output will show progress with `[INFO]`, `[WARN]` messages
- Takes ~10-15 minutes (slow internet to Oracle)
- Server will reboot at the end
- You'll see `Installation complete!` message

---

## Step 5: Verify NixOS Installation

After the installation completes and server reboots (~5 minutes), verify:

```bash
# SSH as root (should work now without password)
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Verify NixOS
nixos-rebuild --version

# Should show: NixOS 24.11

# Check hostname
hostname
# Should show: uptrack-node-india-strong

# Check system info
uname -a
# Should show: Linux uptrack-node-india-strong ... aarch64 GNU/Linux
```

---

## Step 6: Capture SSH Host Key

After successful NixOS installation, add the server's SSH host key to secrets:

```bash
# From your MacBook
ssh-keyscan 144.24.133.171 >> /Users/le/repos/uptrack/infra/nixos/secrets/known_hosts

# Or manually copy host key
ssh-keyscan 144.24.133.171

# Copy the output and add to known_hosts or secrets configuration
```

---

## Step 7: Deploy Application with Colmena

Once NixOS is installed, deploy the application:

```bash
cd /Users/le/repos/uptrack

# Option 1: Deploy only to India Strong
colmena apply --on node-india-strong

# Option 2: Deploy to all nodes
colmena apply --all
```

**What Colmena does:**
- Builds Phoenix release
- Deploys to node
- Configures environment variables
- Starts services (PostgreSQL, Patroni, etcd, app)

---

## Step 8: Verify Services

After deployment:

```bash
# SSH to node
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Check service status
sudo systemctl status | grep -E "postgresql|patroni|etcd|tailscale|uptrack"

# Check logs
sudo journalctl -u uptrack-app -f
sudo journalctl -u postgresql -f
sudo journalctl -u patroni -f
```

---

## Troubleshooting

### Can't connect to instance

See: `INDIA_STRONG_DEBUG.md`

### NixOS installation fails

```bash
# Try with verbose output
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  -i /Users/le/.ssh/ssh-key-2025-10-18.key \
  root@144.24.133.171 \
  --verbose
```

### Patroni won't join cluster

```bash
# Check Patroni logs
sudo journalctl -u patroni -n 50

# Restart Patroni
sudo systemctl restart patroni

# Check cluster status
sudo patronictl list uptrack-pg-cluster
```

### etcd not joining

```bash
# Check etcd logs
sudo journalctl -u etcd -n 50

# Check members
etcdctl member list

# Check health
etcdctl endpoint health --cluster
```

---

## Quick Commands Reference

```bash
# Connection
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Services
sudo systemctl status postgresql
sudo systemctl status patroni
sudo systemctl status etcd
sudo systemctl status tailscale
sudo systemctl status uptrack-app

# Logs
sudo journalctl -u patroni -f
sudo journalctl -u uptrack-app -f
sudo journalctl -xe

# PostgreSQL
psql -U postgres -c "SELECT NOW();"
psql -U postgres -c "SELECT pg_last_wal_receive_lsn();"

# Cluster
patronictl list uptrack-pg-cluster
etcdctl endpoint health --cluster

# System
df -h
free -h
lscpu
uname -a
```

---

## Next Steps After Installation

1. ✅ Verify all services are running
2. ✅ Verify Patroni cluster includes all nodes
3. ✅ Verify etcd cluster has all members
4. ✅ Verify PostgreSQL replication is working
5. ✅ Set up monitoring and alerting
6. ✅ Configure backups

---

## Important Notes

- **ARM64 Only**: This node uses ARM64 architecture - standard x86 binaries won't work
- **Building on Target**: `buildOnTarget = true` in flake.nix means builds happen on the server (saves bandwidth for slow networks)
- **Secrets**: Keep SSH key safe: `ssh-key-2025-10-18.key`
- **Network**: Uses Tailscale for private networking between nodes
- **Database**: PostgreSQL runs in REPLICA mode - replication from Primary (Germany node)

---

**Status**: Ready to begin installation
**Last Updated**: 2025-10-19
**Contact**: Refer to deployment team for issues
