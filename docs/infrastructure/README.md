# Infrastructure Documentation

Quick reference for Uptrack infrastructure deployment and operations.

## Current Infrastructure (4 Nodes)

### EU Nodes (Hostkey Italy)
- **eu-a:** 194.180.207.223 → Tailscale: 100.64.1.1
- **eu-b:** 194.180.207.225 → Tailscale: 100.64.1.2
- **eu-c:** 194.180.207.226 → Tailscale: 100.64.1.3

### India Nodes (Oracle Cloud)
- **india-rworker:** 144.24.150.48 → Tailscale: 100.64.1.11

## Quick Start Guides

### Deploy Tailscale (First Time Setup)
- **OpenSpec:** `openspec/changes/deploy-tailscale-mesh-network/`
- **Quick Start:** [`QUICKSTART-tailscale.md`](./QUICKSTART-tailscale.md)
- **Step-by-Step:** [`DEPLOY-NOW.md`](./DEPLOY-NOW.md)
- **Full Guide:** [`tailscale-deployment-guide.md`](./tailscale-deployment-guide.md)

### Node Information
- **Inventory:** [`node-inventory.md`](./node-inventory.md) - Complete node specs, IPs, SSH commands

## Deployment Scripts

Located in `/scripts/`:
- `install-tailscale-debian.sh` - Deploy to Debian/Ubuntu nodes
- `deploy-tailscale-all.sh` - Deploy to all 4 nodes sequentially

## NixOS Configuration

Located in `/infra/nixos/`:
- `modules/services/tailscale.nix` - Tailscale module
- `regions/asia/india-hyderabad/rworker/` - india-rworker configuration

## OpenSpec Changes

View implementation plans:
```bash
openspec list                    # List all changes
openspec show deploy-tailscale-mesh-network  # View Tailscale deployment spec
```

## Common Tasks

### SSH to Nodes via Tailscale
```bash
ssh root@100.64.1.11    # india-rworker
ssh root@100.64.1.1     # eu-a
ssh root@100.64.1.2     # eu-b
ssh root@100.64.1.3     # eu-c
```

### Check Tailscale Status
```bash
ssh <user>@<ip> 'sudo tailscale status'
ssh <user>@<ip> 'sudo tailscale ip -4'
```

### Ping All Nodes from india-rworker
```bash
ssh root@144.24.150.48
ping -c 3 100.64.1.1   # eu-a
ping -c 3 100.64.1.2   # eu-b
ping -c 3 100.64.1.3   # eu-c
```

## Tailscale Admin

- **Console:** https://login.tailscale.com/admin/machines
- **Account:** hoangbytes@gmail.com
- **Auth Key Expires:** Jan 28, 2026

## Next Steps

After Tailscale deployment completes:
1. ✅ Tailscale mesh network (Phase 1)
2. ⏳ etcd cluster deployment (Phase 2)
3. ⏳ PostgreSQL HA with Patroni (Phase 3)
4. ⏳ VictoriaMetrics cluster (Phase 4)

See: `openspec/changes/1-monitoring-infrastructure/` for full plan
