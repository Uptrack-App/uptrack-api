# Execute Tailscale Deployment - Copy/Paste Commands

**Time Required:** 1-2 hours
**OpenSpec:** `deploy-tailscale-mesh-network`

## Step 1: Test SSH Access (2 minutes)

Open your terminal and run these commands to verify SSH access:

```bash
# Test india-s (NixOS)
ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 le@152.67.179.42 "echo 'india-s: OK'; hostname"

# Test india-w
ssh -o ConnectTimeout=5 root@144.24.150.48 "echo 'india-w: OK'; hostname"

# Test eu-a
ssh -o ConnectTimeout=5 root@194.180.207.223 "echo 'eu-a: OK'; hostname"

# Test eu-b
ssh -o ConnectTimeout=5 root@194.180.207.225 "echo 'eu-b: OK'; hostname"

# Test eu-c
ssh -o ConnectTimeout=5 root@194.180.207.226 "echo 'eu-c: OK'; hostname"
```

**Expected:** Each command should print "OK" and the hostname.

**If any fail:** Fix SSH access before continuing. Check:
- Correct IP address
- SSH key exists: `ls -la ~/.ssh/id_ed25519`
- Node is online
- Firewall allows SSH (port 22)

---

## Step 2: Deploy Tailscale (Automated) (45 minutes)

### Option A: Deploy All at Once (Recommended)

```bash
cd ~/repos/uptrack
./scripts/deploy-tailscale-all.sh
```

This script will:
1. Test SSH to all nodes
2. Deploy to india-s (NixOS) - **15-20 minutes first build**
3. Deploy to india-w - **2 minutes**
4. Deploy to eu-a - **2 minutes**
5. Deploy to eu-b - **2 minutes**
6. Deploy to eu-c - **2 minutes**

**Total time:** ~25-30 minutes

### Option B: Deploy One by One (Manual Control)

If you prefer to deploy step-by-step:

#### 2.1: Deploy to india-s (NixOS)

```bash
cd ~/repos/uptrack

# Set auth key
export TAILSCALE_AUTHKEY="tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg"

# Deploy
./scripts/deploy-tailscale-india-s.sh
```

**Duration:** 15-20 minutes (first build), 5-10 minutes (subsequent)

**Watch for:**
- ✅ "Code synced"
- ✅ "building the system configuration..."
- ✅ "Tailscale connected successfully"
- ✅ "Tailscale IP: 100.64.x.x"

#### 2.2: Deploy to india-w

```bash
cat scripts/install-tailscale-debian.sh | ssh root@144.24.150.48 'bash -s india-w tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
```

**Duration:** 2-3 minutes

**Watch for:**
- ✅ "Installing Tailscale for Debian/Ubuntu..."
- ✅ "✓ Tailscale installed"
- ✅ "✓ Tailscale connected"
- ✅ "IPv4: 100.64.x.x"

#### 2.3: Deploy to eu-a

```bash
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.223 'bash -s eu-a tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
```

#### 2.4: Deploy to eu-b

```bash
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.225 'bash -s eu-b tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
```

#### 2.5: Deploy to eu-c

```bash
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.226 'bash -s eu-c tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd17fk2Fmgnzg'
```

---

## Step 3: Verify All Nodes Online (1 minute)

Go to Tailscale admin console:

**URL:** https://login.tailscale.com/admin/machines

**Expected:** You should see 5 machines online:
- india-s (100.64.x.x) - tag:infrastructure
- india-w (100.64.x.x) - tag:infrastructure
- eu-a (100.64.x.x) - tag:infrastructure
- eu-b (100.64.x.x) - tag:infrastructure
- eu-c (100.64.x.x) - tag:infrastructure

**Screenshot what you see and share if you need help.**

---

## Step 4: Assign Static IPs (5 minutes)

In Tailscale admin console (https://login.tailscale.com/admin/machines):

### For each machine:

1. **Click the machine name** (e.g., "india-s")
2. **Click the ⚙️ (settings icon)** on the right
3. **Click "Edit IP address"**
4. **Enter the static IP** according to this table:

| Machine | Current IP | Static IP |
|---------|-----------|-----------|
| india-s | 100.64.x.x | **100.64.1.10** |
| india-w | 100.64.x.x | **100.64.1.11** |
| eu-a | 100.64.x.x | **100.64.1.1** |
| eu-b | 100.64.x.x | **100.64.1.2** |
| eu-c | 100.64.x.x | **100.64.1.3** |

5. **Click "Save"**
6. **Wait 10 seconds** for changes to propagate

### Verify Static IPs

Run these commands to verify:

```bash
# Verify india-s
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 'sudo tailscale ip -4'
# Expected: 100.64.1.10

# Verify india-w
ssh root@144.24.150.48 'sudo tailscale ip -4'
# Expected: 100.64.1.11

# Verify eu-a
ssh root@194.180.207.223 'sudo tailscale ip -4'
# Expected: 100.64.1.1

# Verify eu-b
ssh root@194.180.207.225 'sudo tailscale ip -4'
# Expected: 100.64.1.2

# Verify eu-c
ssh root@194.180.207.226 'sudo tailscale ip -4'
# Expected: 100.64.1.3
```

---

## Step 5: Test Connectivity (5 minutes)

### Test Ping (EU Internal)

```bash
# From eu-a, ping eu-b
ssh root@194.180.207.223 'ping -c 3 100.64.1.2'
# Expected: <20ms latency

# From eu-a, ping eu-c
ssh root@194.180.207.223 'ping -c 3 100.64.1.3'
# Expected: <20ms latency
```

### Test Ping (Cross-Region)

```bash
# From india-s, ping eu-a
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 'ping -c 3 100.64.1.1'
# Expected: ~150ms latency

# From india-s, ping india-w
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 'ping -c 3 100.64.1.11'
# Expected: <10ms latency
```

### Test SSH via Tailscale

```bash
# SSH to india-s via Tailscale IP
ssh -i ~/.ssh/id_ed25519 le@100.64.1.10 'hostname'
# Expected: uptrack-india-hyderabad-1

# SSH to eu-a via Tailscale IP
ssh root@100.64.1.1 'hostname'
# Expected: hostname of eu-a
```

**If SSH via Tailscale IP works:** ✅ Mesh network is working!

---

## Step 6: Test Auto-Restart (Optional) (5 minutes)

Verify Tailscale auto-starts after reboot:

```bash
# Reboot india-s
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 'sudo reboot'

# Wait 60 seconds for boot
sleep 60

# Check if online in Tailscale admin
# Go to: https://login.tailscale.com/admin/machines
# india-s should show "Online"

# Verify Tailscale IP unchanged
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 'sudo tailscale ip -4'
# Expected: 100.64.1.10
```

---

## Success Criteria

✅ All 5 nodes visible in Tailscale admin console
✅ All nodes have correct static IPs assigned
✅ Ping works between all nodes
✅ SSH works via Tailscale IPs
✅ Latency meets expectations (EU <20ms, cross-region ~150ms)
✅ Auto-restart verified (optional but recommended)

---

## If Something Goes Wrong

### Deployment fails on india-s

```bash
# Check logs
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
sudo journalctl -u tailscaled -n 50

# Rollback if needed
sudo nixos-rebuild switch --rollback
```

### Node doesn't appear in admin console

```bash
# Check if tailscaled is running
ssh <user>@<ip> 'systemctl status tailscaled'

# Restart if needed
ssh <user>@<ip> 'sudo systemctl restart tailscaled'

# Check logs
ssh <user>@<ip> 'sudo journalctl -u tailscaled -n 50'
```

### Cannot ping other nodes

```bash
# Check Tailscale status
ssh <user>@<ip> 'sudo tailscale status'

# Check if IP is correct
ssh <user>@<ip> 'sudo tailscale ip -4'

# Try pinging from both directions
ssh <user>@<node1-ip> 'ping -c 3 <node2-tailscale-ip>'
ssh <user>@<node2-ip> 'ping -c 3 <node1-tailscale-ip>'
```

---

## After Deployment Complete

Update OpenSpec status:

```bash
cd ~/repos/uptrack
openspec show deploy-tailscale-mesh-network
```

Commit the infrastructure code:

```bash
git add .
git commit -m "feat(infra): deploy Tailscale mesh network

- Deployed Tailscale to all 5 nodes (3 EU + 2 India)
- Assigned static IPs: 100.64.1.1-3, 100.64.1.10-11
- Verified mesh connectivity
- All nodes online and reachable

Closes: deploy-tailscale-mesh-network"

git push
```

---

## Next Steps

After Tailscale is fully deployed:

1. ✅ **Phase 1 Complete:** Secure networking established
2. ⏳ **Phase 2:** Deploy etcd cluster (EU nodes only)
3. ⏳ **Phase 3:** Deploy PostgreSQL with Patroni HA
4. ⏳ **Phase 4:** Deploy VictoriaMetrics cluster

See: `openspec/changes/1-monitoring-infrastructure/`
