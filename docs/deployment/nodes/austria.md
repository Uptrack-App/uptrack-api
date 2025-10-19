# Deploy Austria Node (Netcup ARM G11)

**Node**: Austria
**Provider**: Netcup
**Specs**: 6 vCore ARM64, 8 GB RAM, 256 GB NVMe
**Cost**: $7.11/month
**Role**: ClickHouse PRIMARY + PostgreSQL REPLICA

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

**ClickHouse PRIMARY**
- Accepts all monitoring data writes
- Replicates to: Germany, India Strong
- 14-month retention (~120 GB)

**PostgreSQL REPLICA**
- Read-only replica from Germany primary
- Can be promoted to primary if Germany fails

---

## Key Services

- ✅ PostgreSQL 16 + Patroni
- ✅ ClickHouse
- ✅ etcd member (2/5)
- ✅ Phoenix app
- ✅ Oban workers
- ✅ HAProxy

---

## Verification

```bash
ssh root@AUSTRIA_IP

# Check ClickHouse (should be primary)
clickhouse-client -q "SELECT version()"

# Check Patroni (should be replica)
patronictl list uptrack-pg-cluster

# Check etcd
etcdctl endpoint health --cluster

# Check replication lag
clickhouse-client -q "SELECT * FROM system.replicas"
```

---

**Status**: Production Node 2/5
