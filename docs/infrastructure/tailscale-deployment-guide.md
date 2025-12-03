# Tailscale Deployment Guide

Complete guide for deploying Tailscale across all 5 infrastructure nodes.

## Overview

- **Tailscale Account:** hoangbytes@gmail.com
- **Auth Key:** `tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg`
- **Expiration:** Jan 28, 2026
- **Tag:** `tag:infrastructure`

## Target Topology

```
┌──────────────────────────────────────────────────────────┐
│                   Tailscale Mesh Network                 │
│                    (100.64.1.0/24)                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  EU Nodes (Italy/Austria)                                │
│  ├─ eu-a     → 100.64.1.1  (Hostkey Italy)              │
│  ├─ eu-b     → 100.64.1.2  (Hostkey Italy)              │
│  └─ eu-c     → 100.64.1.3  (Hostkey Italy)              │
│                                                          │
│  India Nodes (Oracle Cloud)                              │
│  ├─ india-s  → 100.64.1.10 (Hyderabad - Strong)         │
│  └─ india-w  → 100.64.1.11 (Mumbai - Weak)              │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## Pre-Deployment Checklist

- [x] Tailscale account created (hoangbytes@gmail.com)
- [x] Auth key generated (expires Jan 28, 2026)
- [x] Tag `infrastructure` created
- [ ] SSH access confirmed to all 5 nodes
- [ ] Node IPs documented in `node-inventory.md`

## Installation Methods

### Method A: NixOS Nodes (india-s)

**Node:** india-s (152.67.179.42)

1. **Configuration already added** to `infra/nixos/regions/asia/india-hyderabad/worker-1/default.nix`

2. **Deploy using NixOS rebuild:**
   ```bash
   # Set auth key as environment variable (one-time use)
   export TAILSCALE_AUTHKEY="tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg"

   # SSH to the node
   ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

   # Build and activate new configuration
   cd /etc/nixos  # Or wherever your config is
   sudo TAILSCALE_AUTHKEY="$TAILSCALE_AUTHKEY" nixos-rebuild switch --flake '.#node-india-strong'
   ```

3. **Verify installation:**
   ```bash
   sudo tailscale status
   sudo tailscale ip -4
   ```

4. **Expected output:**
   ```
   100.64.x.x   india-s              hoangbytes@  linux   -
   ```

### Method B: Debian/Ubuntu Nodes (EU + india-w)

**Nodes:** eu-a, eu-b, eu-c, india-w

#### Option 1: Run script locally and SSH to each node

```bash
# Copy script to each node
scp scripts/install-tailscale-debian.sh root@<node-ip>:/tmp/

# SSH and run
ssh root@<node-ip>
chmod +x /tmp/install-tailscale-debian.sh
/tmp/install-tailscale-debian.sh <hostname> tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg

# Example for eu-a:
ssh root@<eu-a-ip>
/tmp/install-tailscale-debian.sh eu-a tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg
```

#### Option 2: One-liner remote execution

```bash
# For eu-a
cat scripts/install-tailscale-debian.sh | ssh root@<eu-a-ip> 'bash -s eu-a tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'

# For eu-b
cat scripts/install-tailscale-debian.sh | ssh root@<eu-b-ip> 'bash -s eu-b tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'

# For eu-c
cat scripts/install-tailscale-debian.sh | ssh root@<eu-c-ip> 'bash -s eu-c tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'

# For india-w
cat scripts/install-tailscale-debian.sh | ssh ubuntu@<india-w-ip> 'bash -s india-w tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
```

## Post-Installation: Assign Static IPs

After all nodes are connected, assign static Tailscale IPs:

1. **Go to Tailscale Admin Console:**
   https://login.tailscale.com/admin/machines

2. **For each machine, assign static IP:**

   | Machine | Current IP | Static IP | Steps |
   |---------|-----------|-----------|-------|
   | india-s | 100.64.x.x | 100.64.1.10 | Click machine → ⚙️ → Edit IP address → Enter `100.64.1.10` → Save |
   | india-w | 100.64.x.x | 100.64.1.11 | Click machine → ⚙️ → Edit IP address → Enter `100.64.1.11` → Save |
   | eu-a | 100.64.x.x | 100.64.1.1 | Click machine → ⚙️ → Edit IP address → Enter `100.64.1.1` → Save |
   | eu-b | 100.64.x.x | 100.64.1.2 | Click machine → ⚙️ → Edit IP address → Enter `100.64.1.2` → Save |
   | eu-c | 100.64.x.x | 100.64.1.3 | Click machine → ⚙️ → Edit IP address → Enter `100.64.1.3` → Save |

3. **Screenshot of expected admin console:**
   ```
   ✓ india-s     100.64.1.10   tag:infrastructure   Online
   ✓ india-w     100.64.1.11   tag:infrastructure   Online
   ✓ eu-a        100.64.1.1    tag:infrastructure   Online
   ✓ eu-b        100.64.1.2    tag:infrastructure   Online
   ✓ eu-c        100.64.1.3    tag:infrastructure   Online
   ```

## Verification Tests

### Test 1: Check Tailscale Status on Each Node

```bash
# SSH to each node and run:
tailscale status
tailscale ip -4

# Expected output:
# 100.64.1.X   <hostname>   hoangbytes@  linux   active; relay "xxx"
```

### Test 2: Ping Between Nodes

From **india-s** (100.64.1.10), ping all other nodes:

```bash
ssh le@152.67.179.42

# Ping EU nodes
ping -c 3 100.64.1.1   # eu-a
ping -c 3 100.64.1.2   # eu-b
ping -c 3 100.64.1.3   # eu-c

# Ping India weak
ping -c 3 100.64.1.11  # india-w
```

**Expected latency:**
- india-s → india-w: <10ms
- india-s → EU nodes: ~150ms

### Test 3: SSH Over Tailscale

```bash
# From your local machine, SSH via Tailscale IPs
ssh root@100.64.1.1   # eu-a
ssh root@100.64.1.2   # eu-b
ssh root@100.64.1.3   # eu-c
ssh le@100.64.1.10    # india-s
ssh ubuntu@100.64.1.11  # india-w (adjust user as needed)
```

### Test 4: DNS Resolution (MagicDNS)

Tailscale provides automatic DNS for hostnames:

```bash
# From any node, ping by hostname
ping -c 3 india-s
ping -c 3 eu-a
ping -c 3 eu-b
```

## Troubleshooting

### Node Shows "Offline" in Admin Console

```bash
# Check Tailscale daemon status
systemctl status tailscaled

# Restart if needed
sudo systemctl restart tailscaled

# Check logs
journalctl -u tailscaled -n 50
```

### Cannot Ping Other Nodes

```bash
# Check Tailscale status
tailscale status

# Check routes
tailscale netcheck

# Verify firewall allows Tailscale
sudo iptables -L -n | grep tailscale
```

### Auth Key Expired

If auth key expires (Jan 28, 2026), generate a new one:

1. Go to **Settings** → **Keys** → **Auth keys**
2. Generate new reusable, ephemeral key with `tag:infrastructure`
3. Update this guide with new key
4. Re-run installation on any new nodes

### Node Has Wrong IP

If node gets wrong IP (e.g., 100.64.1.99 instead of 100.64.1.1):

1. Go to admin console
2. Click machine → ⚙️ → Edit IP address
3. Enter correct static IP
4. Save
5. Wait 10 seconds for change to propagate

## Security Notes

1. **Auth Key Security:**
   - Auth key is reusable but ephemeral
   - If compromised, revoke in admin console: Settings → Keys → Delete key
   - Generate new key and redeploy

2. **Firewall Configuration:**
   - Tailscale interface (`tailscale0`) is trusted
   - All inter-node traffic encrypted via WireGuard
   - No additional firewall rules needed for inter-node communication

3. **Access Control Lists (ACLs):**
   - All nodes tagged with `tag:infrastructure`
   - Future: Define ACL policies in admin console to restrict access
   - Example: Only `tag:infrastructure` can access PostgreSQL port 5432

## Next Steps After Tailscale Deployment

Once all nodes are connected and static IPs assigned:

- [ ] Update `node-inventory.md` with Tailscale IPs
- [ ] Begin Phase 2: etcd cluster deployment
- [ ] Update NixOS configs to use Tailscale IPs for service communication
- [ ] Document provider-specific public IPs (for backup access)

## Reference

- **Tailscale Docs:** https://tailscale.com/kb
- **Admin Console:** https://login.tailscale.com/admin
- **Status Page:** https://status.tailscale.com
