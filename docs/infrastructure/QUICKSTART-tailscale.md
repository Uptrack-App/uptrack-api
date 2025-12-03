# Tailscale Quick Start - Copy/Paste Commands

Quick reference for deploying Tailscale. See `tailscale-deployment-guide.md` for detailed instructions.

## Prerequisites

```bash
# 1. Update node-inventory.md with actual node IPs
vim docs/infrastructure/node-inventory.md

# 2. Verify SSH access to all nodes
ssh le@152.67.179.42  # india-s ✓
ssh root@<eu-a-ip>    # eu-a (TODO: fill IP)
ssh root@<eu-b-ip>    # eu-b (TODO: fill IP)
ssh root@<eu-c-ip>    # eu-c (TODO: fill IP)
ssh ubuntu@<india-w-ip>  # india-w (TODO: fill IP)
```

## Deploy to india-s (NixOS) - 152.67.179.42

```bash
# Set auth key environment variable
export TAILSCALE_AUTHKEY="REMOVED_TAILSCALE_AUTH_KEY"

# SSH to node
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Deploy NixOS configuration (3 steps: validate, build, switch)
cd ~/repos/uptrack/infra/nixos

# Step 1: Validate config
sudo nixos-rebuild dry-build --flake '.#node-india-strong'

# Step 2: Build (15-20 min first time, 5-10 min subsequent)
sudo nixos-rebuild build --flake '.#node-india-strong' --max-jobs 3

# Step 3: Switch (activates Tailscale, installs on boot)
sudo TAILSCALE_AUTHKEY="$TAILSCALE_AUTHKEY" nixos-rebuild switch --flake '.#node-india-strong'

# Verify
sudo tailscale status
sudo tailscale ip -4
```

## Deploy to EU Nodes (Debian/Ubuntu)

Replace `<eu-X-ip>` with actual IPs from node-inventory.md.

### eu-a

```bash
cat scripts/install-tailscale-debian.sh | ssh root@<eu-a-ip> 'bash -s eu-a REMOVED_TAILSCALE_AUTH_KEY'
```

### eu-b

```bash
cat scripts/install-tailscale-debian.sh | ssh root@<eu-b-ip> 'bash -s eu-b REMOVED_TAILSCALE_AUTH_KEY'
```

### eu-c

```bash
cat scripts/install-tailscale-debian.sh | ssh root@<eu-c-ip> 'bash -s eu-c REMOVED_TAILSCALE_AUTH_KEY'
```

## Deploy to india-w (Oracle Ubuntu)

Replace `<india-w-ip>` with actual IP.

```bash
cat scripts/install-tailscale-debian.sh | ssh ubuntu@<india-w-ip> 'bash -s india-w REMOVED_TAILSCALE_AUTH_KEY'
```

## Assign Static IPs

1. Go to: https://login.tailscale.com/admin/machines
2. For each machine:
   - Click machine name
   - Click ⚙️ (settings)
   - Click "Edit IP address"
   - Enter static IP:
     - india-s → `100.64.1.10`
     - india-w → `100.64.1.11`
     - eu-a → `100.64.1.1`
     - eu-b → `100.64.1.2`
     - eu-c → `100.64.1.3`
   - Click "Save"

## Verify Connectivity

From any node, test ping all others:

```bash
# From india-s
ssh le@152.67.179.42

ping -c 3 100.64.1.1   # eu-a (~150ms)
ping -c 3 100.64.1.2   # eu-b (~150ms)
ping -c 3 100.64.1.3   # eu-c (~150ms)
ping -c 3 100.64.1.11  # india-w (<10ms)
```

## Test SSH Over Tailscale

From your local machine:

```bash
ssh le@100.64.1.10     # india-s
ssh ubuntu@100.64.1.11 # india-w (adjust user)
ssh root@100.64.1.1    # eu-a (adjust user)
ssh root@100.64.1.2    # eu-b (adjust user)
ssh root@100.64.1.3    # eu-c (adjust user)
```

## Troubleshooting One-Liners

```bash
# Check status on any node
ssh <user>@<ip> 'sudo tailscale status'

# Check Tailscale IP
ssh <user>@<ip> 'sudo tailscale ip -4'

# Restart Tailscale daemon
ssh <user>@<ip> 'sudo systemctl restart tailscaled'

# Check logs
ssh <user>@<ip> 'sudo journalctl -u tailscaled -n 50'
```

## Success Criteria

✅ All 5 nodes visible in admin console
✅ All nodes have correct static IPs (100.64.1.1-3, 100.64.1.10-11)
✅ All nodes show "Online" status
✅ Ping works between all nodes
✅ SSH works via Tailscale IPs
✅ Latency matches expectations (EU <20ms, India-EU ~150ms)

## Next Steps

After Tailscale is fully deployed and tested:

```bash
# Update node inventory with Tailscale IPs
vim docs/infrastructure/node-inventory.md

# Commit the infrastructure config
git add infra/nixos/modules/services/tailscale.nix
git add infra/nixos/regions/asia/india-hyderabad/worker-1/default.nix
git add scripts/install-tailscale-debian.sh
git add docs/infrastructure/
git commit -m "feat(infra): add Tailscale mesh network

- Created Tailscale module for NixOS
- Deployed on india-s (100.64.1.10)
- Installation scripts for EU nodes + india-w
- Static IPs: 100.64.1.1-3 (EU), 100.64.1.10-11 (India)
- Tag: infrastructure"

# Begin Phase 2: etcd cluster setup
# See: openspec/changes/1-monitoring-infrastructure/tasks.md
```
