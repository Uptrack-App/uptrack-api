# India Strong Node - Manual NixOS Installation (ARM64 Oracle)

## Node Details

| Property | Value |
|----------|-------|
| **Name** | uptrack-node-india-strong |
| **Cloud** | Oracle Cloud Free Tier |
| **Region** | ap-south-1 (Hyderabad, India) |
| **IP Address** | 144.24.133.171 |
| **Architecture** | ARM64 (aarch64) |
| **CPU** | Neoverse-N1, 3 cores |
| **RAM** | 17 GB |
| **Disk** | 46.6 GB SSD |
| **SSH Key** | ~/.ssh/ssh-key-2025-10-18.key |
| **Initial OS** | Ubuntu 24.04 LTS |
| **Target OS** | NixOS 25.05 |

---

## Why Manual Installation?

**nixos-anywhere Failed** on this ARM64 Oracle instance because:
- ❌ kexec boot doesn't persist properly on Oracle ARM64
- ❌ System reboots back to Ubuntu after installation attempt
- ❌ No obvious error messages, silent failure

**Manual Installation Works** because:
- ✅ Uses standard NixOS installation flow
- ✅ More control and debugging capability
- ✅ Reliable on ARM64 systems
- ✅ Proven approach

---

## Quick Start

### From MacBook (Step 1-2):

```bash
# Make scripts executable
chmod +x ~/repos/uptrack/manual-nixos-install.sh
chmod +x ~/repos/uptrack/install-nixos-live.sh

# Run automated download and boot
bash ~/repos/uptrack/manual-nixos-install.sh
```

This script will:
1. ✅ Download NixOS 25.05 ARM64 image (5-10 min)
2. ✅ Write image to disk (3-5 min)
3. ✅ Reboot into NixOS live environment (2-3 min)

### On Instance in NixOS Live (Step 3-8):

```bash
# SSH to NixOS live environment
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Copy installation script
# Or paste contents from install-nixos-live.sh

# Run installation
bash install-nixos-live.sh
```

This script will:
1. ✅ Create partitions (EFI + root)
2. ✅ Format filesystems
3. ✅ Generate NixOS config
4. ✅ Install NixOS (10-20 min)
5. ✅ Reboot into installed NixOS

---

## Step-by-Step Installation

### Phase 1: Image Download and Boot (From MacBook)

**Time: ~15 minutes**

```bash
cd ~/repos/uptrack

# Run automated script
bash manual-nixos-install.sh
```

**What happens:**
1. Connects as `ubuntu` user
2. Downloads NixOS 25.05 ARM64 (356 MB compressed, ~1.2 GB uncompressed)
3. Decompresses image
4. Writes to /dev/sda using `dd`
5. Reboots system
6. Waits for NixOS live environment to boot

**Expected output:**
```
✓ Connected
✓ Image downloaded
✓ Image decompressed
✓ Image written
✓ Waiting for system to boot NixOS (3-5 minutes)...
✓ NixOS live environment online
✓ You're now in NixOS live environment
```

---

### Phase 2: Partition and Install (On Instance)

**Time: ~40 minutes**

```bash
# SSH to live NixOS
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Create installation script (or copy from repo)
cat > /root/install-nixos.sh << 'EOF'
#!/bin/bash
set -e

# Step 1: Create partitions
echo "Creating partitions on /dev/sda..."
parted -s /dev/sda mklabel gpt
parted -s /dev/sda mkpart primary fat32 1M 512M
parted -s /dev/sda mkpart primary ext4 512M 100%
parted -s /dev/sda set 1 boot on

# Step 2: Format partitions
echo "Formatting partitions..."
mkfs.fat -F 32 /dev/sda1
mkfs.ext4 /dev/sda2

# Step 3: Mount partitions
echo "Mounting partitions..."
mount /dev/sda2 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Step 4: Generate config
echo "Generating NixOS configuration..."
nixos-generate-config --root /mnt

# Step 5: Install NixOS
echo "Installing NixOS (this takes 10-20 minutes)..."
nixos-install --root /mnt

# Step 6: Reboot
echo "Installation complete! Rebooting..."
umount -R /mnt
reboot
EOF

chmod +x /root/install-nixos.sh
bash /root/install-nixos.sh
```

**What happens:**
1. Creates partitions (512M EFI + 46G root)
2. Formats with FAT32 and ext4
3. Mounts to /mnt
4. Generates hardware config
5. Installs NixOS (takes 10-20 minutes)
6. Reboots into NixOS

---

### Phase 3: Post-Installation Deployment

**Time: ~10 minutes**

After reboot, NixOS is installed but basic. Deploy full configuration:

```bash
# SSH as root to new NixOS
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Clone repo (if not already there)
cd /root
git clone https://github.com/your-repo/uptrack.git

# Or copy from MacBook
scp -r ~/repos/uptrack root@144.24.133.171:/root/

# Deploy Uptrack services
cd /root/uptrack
sudo nixos-rebuild switch --flake .#node-india-strong

# Wait for services to start (5-10 minutes)
systemctl status postgresql patroni etcd clickhouse-server uptrack-app
```

---

## Disk Layout After Installation

```
/dev/sda
├── /dev/sda1  (512M)   EFI System Partition    /boot/efi
└── /dev/sda2  (46G)    Linux Root Partition    /
```

---

## Service Verification

After full deployment, verify services:

```bash
# SSH to node
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Check all services
sudo systemctl status | grep -E 'postgresql|patroni|etcd|clickhouse|uptrack'

# Specific service checks
sudo systemctl status postgresql      # Database
sudo systemctl status patroni         # HA coordinator
sudo systemctl status etcd            # Consensus
sudo systemctl status clickhouse-server  # Time-series
sudo systemctl status uptrack-app     # Application

# Check logs
sudo journalctl -u postgresql -f
sudo journalctl -u uptrack-app -f
```

---

## Troubleshooting

### Issue 1: Image Download Fails

**Error:** Cannot download image

**Solution:**
```bash
# Try alternative mirror
curl -L https://nixos.org/releases/nixos/unstable-aarch64-linux/latest-nixos-sd-image-aarch64-linux.img.zst \
  -o nixos-image.img.zst
```

### Issue 2: DD Write Fails

**Error:** "No space left on device"

**Solution:**
- Oracle might be allocating more volumes
- Check with: `lsblk` to see all volumes
- May need to partition differently

### Issue 3: Installation Hangs

**Issue:** Installation seems stuck

**Solution:**
- ✅ This is NORMAL - wait 20 minutes
- Installation can take 20-30 minutes on slow connections
- Check system load: `top` (in another SSH session)

### Issue 4: SSH Fails After Reboot

**Error:** "Connection refused" or "Operation timed out"

**Solution:**
```bash
# Wait 5 minutes for system to fully boot
sleep 300

# Try again
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
```

### Issue 5: Services Not Starting

**Issue:** Services show "inactive"

**Solution:**
```bash
# Wait - services take time to start
sleep 60

# Check logs for errors
sudo journalctl -u postgresql -n 50
sudo journalctl -u patroni -n 50

# Restart manually if needed
sudo systemctl restart postgresql
sudo systemctl restart patroni
```

---

## Timeline

| Phase | Time | Task |
|-------|------|------|
| 1 | 15 min | Download image, write to disk, reboot |
| 2 | 40 min | Partition, format, install NixOS |
| 3 | 5 min | System boot into NixOS |
| 4 | 10 min | Deploy services with colmena |
| **Total** | **70 min** | **Complete installation** |

---

## Post-Installation

### Backup Important Config

```bash
# Backup Nix store
sudo nixos-rebuild list-generations

# Backup SSH keys
sudo tar -czf /root/ssh-keys-backup.tar.gz /etc/ssh/
```

### Monitor Services

```bash
# Real-time monitoring
watch -n 1 'systemctl status postgresql patroni etcd clickhouse-server uptrack-app'

# Check cluster status
patronictl list uptrack-pg-cluster
etcdctl endpoint health --cluster
```

### Update/Rebuild

```bash
# After code changes
cd ~/repos/uptrack
git pull
nixos-rebuild switch --flake .#node-india-strong
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `manual-nixos-install.sh` | Automated download & boot (run from MacBook) |
| `install-nixos-live.sh` | Partition & install (run in NixOS live) |
| `/flake.nix` | Uptrack configuration |
| `infra/nixos/node-india-strong.nix` | Node-specific config |

---

## SSH Key

**Location:** `~/.ssh/ssh-key-2025-10-18.key`
**Permissions:** 600 (read-only by owner)
**Type:** ED25519
**Usage:** All SSH connections to India Strong

---

## Network

**Private IP:** 10.0.0.198
**Public IP:** 144.24.133.171
**VCN:** vcn-uptrack-ch-pri
**Subnet:** sb-uptrack-ch-pri
**Network Interface:** enp0s6 (9000 MTU)

---

## Estimated Costs

- **CPU**: Always-free tier
- **Storage**: 46.6 GB (within free tier)
- **Bandwidth**: Within free tier
- **Total**: $0 USD

---

## Related Documentation

- `MANUAL_NIXOS_INSTALL.md` - Detailed installation guide
- `docs/oracle/ORACLE_SETUP_CHECKLIST.md` - Oracle networking setup
- `docs/oracle/route_table.md` - Route table configuration
- `docs/ssh_key_permissions.md` - SSH key troubleshooting

---

**Last Updated:** 2025-10-19
**Status:** Ready for manual installation
**Architecture:** ARM64 (aarch64)
**Estimated Duration:** 70 minutes

