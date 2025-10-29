# Deploy Austria Node (Netcup ARM G11)

**Node**: Austria
**Provider**: Netcup
**Specs**: 6 vCore ARM64, 8 GB RAM, 256 GB NVMe
**Cost**: $7.11/month
**Role**: PostgreSQL REPLICA + VictoriaMetrics Node

---

## Quick Start

```bash
# Deploy with nixos-anywhere + Colmena
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-austria \
  -i ssh-key.key \
  root@AUSTRIA_IP

colmena apply --on node-austria
```

---

## Database Role

**VictoriaMetrics Node**
- Part of VM cluster
- Handles time-series metrics
- TODO: Define specific role (vmstorage/vminsert/vmselect)

**PostgreSQL REPLICA**
- Read-only replica from Germany primary
- Can be promoted to primary if Germany fails

---

## Key Services

- ✅ PostgreSQL 16 + Patroni
- ✅ VictoriaMetrics (TODO: configure cluster component)
- ✅ etcd member (2/5)
- ✅ Phoenix app
- ✅ Oban workers
- ✅ HAProxy

---

## Verification

```bash
ssh root@AUSTRIA_IP

# Check VictoriaMetrics
# TODO: Add VM health check commands

# Check Patroni (should be replica)
patronictl list uptrack-pg-cluster

# Check etcd
etcdctl endpoint health --cluster
```

---

**Status**: Production Node 2/5
