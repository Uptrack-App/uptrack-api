# Deploy India Weak Node (Oracle Cloud Free)

**Node**: India Weak
**Provider**: Oracle Cloud Free Tier
**Specs**: 1 ARM64 core, ? GB RAM, ? GB storage
**Cost**: FREE
**Role**: App-only + etcd member

---

## Quick Start

```bash
# Deploy with nixos-anywhere + Colmena
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-weak \
  -i ssh-key.key \
  root@INDIA_WEAK_IP

colmena apply --on node-india-weak
```

---

## Database Role

**NO DATABASES**
- App-only node
- No PostgreSQL
- No VictoriaMetrics
- Connects remotely via Tailscale

---

## Key Services

- ✅ Phoenix app
- ✅ Oban workers (lightweight, APAC regional)
- ✅ etcd member (5/5) - Provides quorum
- ✅ HAProxy
- ✅ Tailscale

---

## Why This Node?

**Purpose**: Completes 5-node etcd cluster (odd number for optimal consensus)

**Benefits**:
- Minimal resource usage (1 CPU is sufficient for app-only)
- Adds geographic redundancy in India
- Provides etcd quorum without database overhead
- Low cost (free Oracle tier)

---

## Key Services

- ✅ Phoenix app
- ✅ Oban workers
- ✅ etcd member (5/5)
- ✅ HAProxy
- ✅ Tailscale

---

## Verification

```bash
ssh root@INDIA_WEAK_IP

# Check etcd
etcdctl endpoint health --cluster
# Should see: 5 members healthy

# Check Tailscale
tailscale status
# Should see: connected, IP 100.64.0.5

# Check app
systemctl status uptrack-app
```

---

**Status**: Production Node 5/5
