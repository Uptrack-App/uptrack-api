# Deploy Canada Node (OVH VPS-1)

**Node**: Canada
**Provider**: OVH
**Specs**: 4 vCore, 8 GB RAM, 75 GB NVMe
**Cost**: $4.20/month
**Role**: App-only (no databases)

---

## Quick Start

```bash
# Deploy with nixos-anywhere + Colmena
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-canada \
  -i ssh-key.key \
  root@CANADA_IP

colmena apply --on node-canada
```

---

## Database Role

**NO LOCAL DATABASES**
- Connects to Germany (Postgres primary)
- Connects to VictoriaMetrics cluster
- Read-only replicas accessible locally via Tailscale

---

## Key Services

- ✅ Phoenix app
- ✅ Oban workers (North America regional checks)
- ✅ etcd member (3/5)
- ✅ HAProxy
- ✅ Tailscale

---

## Verification

```bash
ssh root@CANADA_IP

# Check app running
systemctl status uptrack-app

# Check etcd
etcdctl endpoint health --cluster

# Test database connectivity
psql -U postgres -h 100.64.0.1 -l  # Germany Postgres
# TODO: Add VictoriaMetrics health check
```

---

**Status**: Production Node 3/5
