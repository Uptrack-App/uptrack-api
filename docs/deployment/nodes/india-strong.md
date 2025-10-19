# Deploy India Strong Node with NixOS

**Node**: India Strong (Oracle Cloud)
**IP**: 144.24.133.171
**SSH Key**: ssh-key-2025-10-18.key
**Method**: nixos-anywhere + Colmena

---

## Quick Start

```bash
# 1. Set variables
export INDIA_STRONG_IP="144.24.133.171"
export SSH_KEY="ssh-key-2025-10-18.key"

# 2. Fix SSH key permissions
chmod 400 $SSH_KEY

# 3. Deploy NixOS with nixos-anywhere
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i $SSH_KEY \
  root@$INDIA_STRONG_IP

# 4. After deployment, use Colmena to deploy apps
colmena apply --on node-india-strong
```

---

## Prerequisites

### 1. SSH Key Setup

```bash
# Make key read-only
chmod 400 ssh-key-2025-10-18.key

# Test connection to Oracle instance
ssh -i ssh-key-2025-10-18.key ubuntu@144.24.133.171 "uname -a"
# Expected: Ubuntu on ARM64 (aarch64)
```

### 2. Nix Flakes Enabled

```bash
# Check if flakes are enabled
nix flake show

# If not working, enable in ~/.config/nix/nix.conf:
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 3. Add Node to Flake

Edit `flake.nix` to add India Strong node:

```nix
# After node-c configuration, add:

# Node India Strong - PostgreSQL REPLICA (Oracle Cloud Free Tier)
node-india-strong = {
  deployment = {
    targetHost = "144.24.133.171";
    targetUser = "root";
    tags = [ "india" "oracle" "app" "postgres" "replica" "arm64" ];
    buildOnTarget = true;  # Build on server (slow internet connection)
    allowLocalDeployment = false;
  };

  # Override nixpkgs for ARM64
  nixpkgs.system = "aarch64-linux";

  imports = commonModules ++ [
    ./infra/nixos/node-india-strong.nix
    ./infra/nixos/services/uptrack-app.nix
    ./infra/nixos/services/postgres.nix      # PostgreSQL replica
    ./infra/nixos/services/patroni.nix       # Patroni HA
    ./infra/nixos/services/etcd.nix          # etcd member
    ./infra/nixos/services/tailscale.nix     # Tailscale
  ];
};
```

---

## Step 1: Install NixOS with nixos-anywhere

### Option A: Automatic Installation (Recommended)

```bash
cd /path/to/uptrack

# Deploy NixOS
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i ssh-key-2025-10-18.key \
  root@144.24.133.171
```

**What this does:**
1. ✅ Downloads NixOS 24.11 ARM64 image
2. ✅ Partitions disk (disko configuration)
3. ✅ Installs NixOS base system
4. ✅ Applies all node configurations
5. ✅ Takes ~10-15 minutes

### Option B: Manual if nixos-anywhere Fails

```bash
# SSH to Oracle instance as ubuntu
ssh -i ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Switch to root
sudo su -

# Download NixOS ARM64 installer
wget https://releases.nixos.org/nixos/24.11/nixos-24.11.20250101.8b2b0f1/nixos-sd-image-24.11.20250101.8b2b0f1-aarch64-linux.img.zst

# Decompress
zstd -d nixos-sd-image-*.img.zst

# Write to disk (check dmesg first to find correct device)
dd if=nixos-sd-image-*.img of=/dev/sda bs=4M

# Reboot
reboot
```

---

## Step 2: Verify NixOS Installation

```bash
# After installation, SSH as root
ssh -i ssh-key-2025-10-18.key root@144.24.133.171

# Check NixOS version
nixos-rebuild --version

# Check system info
uname -a
# Expected: Linux uptrack-node-india-strong #1 aarch64 GNU/Linux

# Check available storage
df -h
# Expected: ~145 GB from Oracle block volumes

# Check system resources
free -h
# Expected: ~24 GB RAM

# Check CPU
lscpu | grep -E "CPU|core"
# Expected: ARM64, ~4 cores
```

---

## Step 3: Install Tailscale

```bash
# SSH to node
ssh -i ssh-key-2025-10-18.key root@144.24.133.171

# Tailscale should be in services if configured
# Start Tailscale
sudo systemctl start tailscale

# Authenticate
sudo tailscale up

# Get Tailscale IP
tailscale ip -4
# Save this IP! Should be 100.64.0.4 or similar
```

---

## Step 4: Configure PostgreSQL & Patroni

The NixOS configuration should already handle this, but verify:

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Check Patroni status
sudo systemctl status patroni

# Watch Patroni logs
sudo journalctl -u patroni -f

# Check Patroni cluster
patronictl list uptrack-pg-cluster
```

**Expected output:**
```
+ Cluster: uptrack-pg-cluster ----+---------+----+-----------+
| Member       | Host        | Role    | State   | TL | Lag in MB |
+--------------+-------------+---------+---------+----+-----------+
| germany      | 100.64.0.1  | Leader  | running |  1 |           |
| austria      | 100.64.0.2  | Replica | running |  1 |         0 |
| india-strong | 100.64.0.4  | Replica | running |  1 |         0 |
+--------------+-------------+---------+---------+----+-----------+
```

---

## Step 5: Configure etcd

```bash
# Check etcd status
sudo systemctl status etcd

# Check cluster members
etcdctl member list

# Check cluster health
etcdctl endpoint health --cluster
```

**Expected: 5 members (Germany, Austria, Canada, India Strong, India Weak)**

---

## Step 6: Deploy Phoenix App

```bash
# Using Colmena to deploy app
cd /path/to/uptrack

# Deploy only to India Strong
colmena apply --on node-india-strong

# Or deploy to all nodes
colmena apply --all
```

**What Colmena does:**
1. ✅ Builds Phoenix release
2. ✅ Deploys to India Strong
3. ✅ Configures environment variables
4. ✅ Starts services

---

## Step 7: Verify Deployment

```bash
# SSH to node
ssh -i ssh-key-2025-10-18.key root@144.24.133.171

# Check all services
sudo systemctl status

# Specifically check:
sudo systemctl status postgresql
sudo systemctl status patroni
sudo systemctl status etcd
sudo systemctl status tailscale
sudo systemctl status uptrack-app

# Check app logs
sudo journalctl -u uptrack-app -f

# Check replication lag
psql -U postgres -c "SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;"

# Test PostgreSQL connection from local
psql -U postgres -h 127.0.0.1 -l

# Test connection from Germany
# From Germany node: psql -U postgres -h 100.64.0.4 -l
```

---

## Troubleshooting

### NixOS Installation Failed

```bash
# Check installation logs
tail -100 /var/log/installer.log

# Retry with verbose output
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  -i ssh-key-2025-10-18.key \
  root@144.24.133.171 \
  --verbose
```

### Patroni Not Joining Cluster

```bash
# Check Patroni logs
sudo journalctl -u patroni -n 100

# Common issues:
# 1. etcd not running
sudo systemctl restart etcd

# 2. Replication password wrong - check config:
sudo cat /etc/patroni/patroni.yml | grep password

# 3. Firewall blocking ports:
sudo iptables -L -n | grep 5432
sudo iptables -L -n | grep 2379
```

### Tailscale Not Connected

```bash
# Check Tailscale status
tailscale status

# Re-authenticate if needed
sudo tailscale up

# Check if other nodes can ping
ping 100.64.0.1  # Germany
ping 100.64.0.2  # Austria
ping 100.64.0.3  # Canada
```

### Disk Space Issues

```bash
# Check disk usage
df -h
lsblk

# If only boot volume mounted, mount block volume:
sudo mkdir -p /var/lib/postgresql
sudo mount /dev/vdb /var/lib/postgresql
# Or configure in disko.nix for automatic mounting
```

---

## Rollback / Revert

If something goes wrong, rollback to previous NixOS generation:

```bash
# List previous generations
sudo nixos-rebuild list-generations

# Rollback to previous
sudo nixos-rebuild switch --rollback

# Or switch to specific generation
sudo nixos-rebuild switch --profile-name=system -G 2
```

---

## Update Configuration

After initial deployment, to update configs:

```bash
# Edit configuration in git
vim infra/nixos/node-india-strong.nix

# Redeploy with Colmena
colmena apply --on node-india-strong

# Or just restart services if no system changes
sudo systemctl restart patroni
sudo systemctl restart etcd
sudo systemctl restart uptrack-app
```

---

## Quick Reference Commands

```bash
# Connect to node
ssh -i ssh-key-2025-10-18.key root@144.24.133.171

# Check services
sudo systemctl status | grep "postgresql\|patroni\|etcd\|tailscale"

# View logs
sudo journalctl -u patroni -f
sudo journalctl -u uptrack-app -f

# Reload configuration
sudo nixos-rebuild switch

# Check cluster status
patronictl list uptrack-pg-cluster
etcdctl endpoint health --cluster
tailscale status

# Verify replication
psql -U postgres -c "SELECT NOW(), pg_last_wal_receive_lsn();"
```

---

**Deployment Guide Version**: 1.0
**Last Updated**: 2025-10-19
**Status**: Ready for deployment
