# Uptrack Deployment Documentation

Complete guide for deploying and managing the 5-node Uptrack infrastructure with NixOS.

---

## 📋 Quick Links

### Node Deployment Guides

**All 5 Production Nodes:**

| Node | Provider | Role | Cost | Guide |
|------|----------|------|------|-------|
| **Germany** | Netcup ARM G11 | PG Primary + CH Replica | $7.11/mo | [germany.md](./nodes/germany.md) |
| **Austria** | Netcup ARM G11 | CH Primary + PG Replica | $7.11/mo | [austria.md](./nodes/austria.md) |
| **Canada** | OVH VPS-1 | App-only | $4.20/mo | [canada.md](./nodes/canada.md) |
| **India RWorker** | Oracle Free | Backups & Logs | FREE | [india-rworker.md](./nodes/india-rworker.md) |

---

## 🚀 Deployment Guides

**Getting Started:**

1. **[nixos-general.md](./guides/nixos-general.md)** - General NixOS deployment concepts
2. **[deployment-plan.md](./guides/deployment-plan.md)** - High-level deployment strategy

**Node-Specific:**

---

## Architecture Overview

### Database Distribution

```
PostgreSQL PRIMARY: Germany
├─ Replica 1: Austria

ClickHouse PRIMARY: Austria
├─ Replica 1: Germany

etcd Cluster: All 5 nodes
├─ Quorum: 3/5
└─ Tolerates: 2 failures
```

### Geographic Coverage

- **Europe**: Germany, Austria (database primaries)
- **North America**: Canada (app-only)
- **APAC**: India RWorker (backups & logs)

---

## 🎯 Deployment Sequence

### Phase 1: Germany & Austria (Netcup)

```bash
# 1. Deploy Germany (Postgres PRIMARY)
colmena apply --on node-germany

# 2. Deploy Austria (ClickHouse PRIMARY)
colmena apply --on node-austria

# Verify 2-node cluster
patronictl list uptrack-pg-cluster
etcdctl endpoint health --cluster
```

**Time**: ~20 minutes
**Result**: 2-node database cluster running

---

### Phase 2: Canada (OVH)

```bash
# Deploy Canada (App-only)
colmena apply --on node-canada

# Verify etcd cluster
etcdctl endpoint health --cluster
```

**Time**: ~10 minutes
**Result**: 3-node etcd cluster + app redundancy

---

### Phase 3: India RWorker (Oracle Free)

```bash
# Deploy India RWorker (App-only + etcd)
colmena apply --on india-rworker

# Verify cluster
etcdctl endpoint health --cluster
```

**Time**: ~10 minutes
**Result**: India RWorker deployed

---

## ✅ Verification Checklist

After each node deployment:

### PostgreSQL Cluster

```bash
# Should show Germany as primary, others as replicas
patronictl list uptrack-pg-cluster

# Check replication lag (should be < 100ms)
psql -U postgres -c "SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn();"
```

### ClickHouse Cluster

```bash
# Check replication status
clickhouse-client -q "SELECT * FROM system.replicas"

# Check replication lag
clickhouse-client -q "SELECT database, table, absolute_delay FROM system.replicas"
```

### etcd Cluster

```bash
# Should show all members healthy
etcdctl endpoint health --cluster

# Check member list
etcdctl member list
```

### Applications

```bash
# Check all nodes running
colmena eval --print-graph | grep -E "node-|@"

# View app logs
colmena eval node-germany -- systemctl status uptrack-app
```

---

## 🔧 Common Operations

### Deploy All Nodes

```bash
colmena apply --all
```

### Deploy Single Node

```bash
colmena apply --on node-germany
```

### Rebuild on Node

```bash
colmena eval node-germany -- nixos-rebuild switch
```

### View Node Status

```bash
colmena eval node-germany -- systemctl status uptrack-app
colmena eval node-germany -- systemctl status patroni
```

### SSH to Node

```bash
ssh root@node-germany  # From local SSH config
ssh -i key.key root@GERMANY_IP  # Direct
```

---

## 📈 Scaling

### Add Regional Node

To add a node in a new region (e.g., Tokyo):

1. Create `infra/nixos/node-tokyo.nix`
2. Add to `flake.nix` under colmena nodes
3. Deploy: `colmena apply --on node-tokyo`

Cost: +$4-5/month per app-only node

### Scale Database

To support 20K monitors:

1. Upgrade Netcup nodes to VPS 2000 ARM G11 (512 GB)
2. Update `flake.nix` (no config changes needed)
3. Deploy: `colmena apply --all`

Cost: +$14/month for 2 nodes

---

## 🆘 Troubleshooting

### Patroni Issues

```bash
# Check status
colmena eval node-germany -- systemctl status patroni

# Check logs
colmena eval node-germany -- journalctl -u patroni -f

# Manual recovery (if needed)
colmena eval node-germany -- patronictl reinit uptrack-pg-cluster node-austria
```

### etcd Issues

```bash
# Check cluster
colmena eval node-germany -- etcdctl endpoint health --cluster

# Check members
colmena eval node-germany -- etcdctl member list

# Remove stuck member (rarely needed)
etcdctl member remove <ID>
```

### Replication Lag

```bash
# Check lag
colmena eval node-germany -- psql -U postgres -c "SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn();"

# If high, check network
colmena eval india-rworker -- tailscale status
```

---

## 📚 Related Documentation

**Architecture**:
- [docs/architecture/ARCHITECTURE-SUMMARY.md](../architecture/ARCHITECTURE-SUMMARY.md) - Overview
- [docs/architecture/final-5-node-architecture.md](../architecture/final-5-node-architecture.md) - Detailed specs
- [docs/architecture/why-separate-database-primaries.md](../architecture/why-separate-database-primaries.md) - Design principles

**NixOS**:
- [docs/NIXOS-SETUP-COMPLETE.md](../NIXOS-SETUP-COMPLETE.md) - NixOS setup guide
- [infra/nixos/](../../infra/nixos/) - NixOS configurations

**Operations**:
- [docs/DEPLOYMENT.md](../DEPLOYMENT.md) - General deployment guide
- [docs/architecture/oracle-free-tier-monitoring.md](../architecture/oracle-free-tier-monitoring.md) - Oracle price alerts

---

## 🎓 First-Time Setup

1. Read [ARCHITECTURE-SUMMARY.md](../architecture/ARCHITECTURE-SUMMARY.md)
2. Read [nixos-general.md](./guides/nixos-general.md)
3. Follow [deployment-plan.md](./guides/deployment-plan.md)
4. Deploy nodes in order: Germany → Austria → Canada → India RWorker

---

## 📞 Support

**For issues**:
1. Check troubleshooting section above
2. Check node-specific guide
3. Review logs: `colmena eval node-X -- journalctl -f`
4. Check SSH connectivity: `ssh -v root@NODEIP`

---

**Documentation Version**: 1.0
**Last Updated**: 2025-10-19
**Status**: Production Ready
