# Deploy Germany Node (Netcup ARM G11)

**Node**: Germany
**Provider**: Netcup
**Specs**: 6 vCore ARM64, 8 GB RAM, 256 GB NVMe
**Cost**: $7.11/month
**Role**: PostgreSQL PRIMARY + VictoriaMetrics Node

---

## Quick Start

```bash
# Deploy with nixos-anywhere + Colmena
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-germany \
  -i ssh-key.key \
  root@GERMANY_IP

colmena apply --on node-germany
```

---

## Database Role

**PostgreSQL PRIMARY**
- Accepts all writes
- Replicates to: Austria, India Strong

**VictoriaMetrics Node**
- Part of VM cluster
- Handles time-series metrics
- TODO: Define specific role (vmstorage/vminsert/vmselect)

---

## Key Services

- ✅ PostgreSQL 16 + Patroni
- ✅ VictoriaMetrics (TODO: configure cluster component)
- ✅ etcd member (1/5)
- ✅ Phoenix app
- ✅ Oban workers
- ✅ HAProxy

---

## Verification

```bash
ssh root@GERMANY_IP

# Check Patroni
patronictl list uptrack-pg-cluster

# Check VictoriaMetrics
# TODO: Add VM health check commands

# Check etcd
etcdctl endpoint health --cluster

# Check app
systemctl status uptrack-app
```

---

**Status**: Production Node 1/5
