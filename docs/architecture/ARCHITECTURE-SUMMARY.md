# Uptrack Architecture Summary

**Last Updated**: 2025-10-19
**Status**: Production Ready

---

## Quick Reference

### Final 5-Node Architecture

| Node | Location | Provider | vCore | RAM | Storage | Databases | Cost/mo |
|------|----------|----------|-------|-----|---------|-----------|---------|
| **Germany** | EU | Netcup ARM G11 | 6 | 8 GB | 256 GB | PG Primary + CH Replica | $7.11 |
| **Austria** | EU | Netcup ARM G11 | 6 | 8 GB | 256 GB | CH Primary + PG Replica | $7.11 |
| **Canada** | NA | OVH VPS-1 | 4 | 8 GB | 75 GB | App-only | $4.20 |
| **India Strong** | APAC | Oracle Free | ? | ? | 145 GB | PG Replica | Free |
| **India Weak** | APAC | Oracle Free | 1 | ? | ? | App-only + etcd | Free |

**Total Cost**: ~$23/month (~$276/year)

---

## Database Distribution

### PostgreSQL (Patroni HA Cluster)
- **Primary**: Germany 🇩🇪
- **Replicas**: Austria 🇦🇹, India Strong 🇮🇳
- **Failover**: Automatic (30s RTO)

### ClickHouse (Replication)
- **Primary**: Austria 🇦🇹
- **Replica**: Germany 🇩🇪
- **Retention**: 14 months (~120 GB)
- **Failover**: Manual with disk spooling

### etcd (Consensus Cluster)
- **Members**: Germany, Austria, Canada, India Strong, India Weak
- **Quorum**: 3/5 nodes
- **Tolerates**: 2 node failures

---

## Key Architecture Principles

### ✅ Follows Separation Principle
> "Never put both PostgreSQL PRIMARY and ClickHouse PRIMARY on the same node"

- PostgreSQL PRIMARY: Germany 🇩🇪
- ClickHouse PRIMARY: Austria 🇦🇹
- **Different nodes** = Isolated failures ✅

### ✅ Optimal Resource Usage
- **Both Netcup nodes (256 GB)**: Hold PRIMARY + replica (68% utilization)
- **Canada (75 GB)**: App-only (20% utilization)
- **India nodes**: Replica + app (38% utilization)

### ✅ Geographic Coverage
- **Europe**: 2 nodes (Germany, Austria) - Both database primaries
- **North America**: 1 node (Canada) - App-only
- **APAC**: 2 nodes (India) - Postgres replica + apps

---

## Why This Architecture?

### 1. Cost Effective
- **$23/month** for 5-node HA across 3 continents
- vs **$200+/month** for AWS RDS Multi-AZ + ClickHouse Cloud
- **7-10x cheaper** than managed alternatives

### 2. High Availability
- **PostgreSQL**: Automatic Patroni failover (30s)
- **ClickHouse**: Manual failover with zero data loss (spooling)
- **App**: Instant Cloudflare DNS failover (5s)
- **etcd**: Tolerates 2 node failures

### 3. Scalable
- **Current**: Supports 10K monitors, 14-month retention
- **Add regions**: $4-5/month per app-only node
- **Scale storage**: Upgrade Netcup to 512 GB for 20K monitors
- **Distributed**: Can shard ClickHouse when needed

### 4. Battle-Tested Stack
- **Phoenix + Elixir**: Proven monolith architecture
- **PostgreSQL + Patroni**: Industry-standard HA
- **ClickHouse**: Best-in-class analytics database
- **Tailscale**: Secure private networking
- **Cloudflare**: DDoS protection + CDN

---

## Network Topology

```
Tailscale Private Network:
├─ Germany: 100.64.0.1
├─ Austria: 100.64.0.2
├─ Canada: 100.64.0.3
├─ India Strong: 100.64.0.4
└─ India Weak: 100.64.0.5

Database Connections:
├─ Apps → Postgres PRIMARY: germany:5432 (via HAProxy)
├─ Apps → Postgres replicas: Local when available
└─ Apps → ClickHouse PRIMARY: austria:8123

Public Access:
├─ Cloudflare DNS → All 5 nodes (round-robin)
├─ SSL/TLS → Cloudflare + Let's Encrypt
└─ DDoS Protection → Cloudflare WAF
```

---

## Capacity & Limits

| Resource | Current | Limit | Headroom |
|----------|---------|-------|----------|
| **Monitors** | ~1K | 10K | 10x |
| **Checks/min** | ~3K | 30K | 10x |
| **Storage (CH)** | ~20 GB | 240 GB | 12x |
| **Storage (PG)** | ~10 GB | 80 GB | 8x |
| **Retention** | 14 months | 28 months | 2x |

---

## Scaling Roadmap

### Phase 1: Add Regional Nodes ($4-5 each)
- Tokyo (APAC)
- Singapore (APAC)
- São Paulo (South America)
- **Cost**: +$12-15/month for 3 regions

### Phase 2: Upgrade Storage (20K monitors)
- Netcup VPS 2000 ARM G11 (512 GB): $14/month each
- **Total**: $28/month for Netcup nodes (+$14)

### Phase 3: Distributed ClickHouse (50K+ monitors)
- Shard by region
- Add dedicated ClickHouse nodes
- **Cost**: $80-120/month total

---

## Important Design Decisions

### Why NOT Poland Node?
**Decision**: Remove Poland to save $4.20/month

**Rationale**:
- India Weak can provide 5th etcd member (keeps odd number)
- Poland was app-only (no unique value)
- Still have 2 EU nodes (Germany, Austria)
- Savings: $50/year

### Why Co-locate Databases on Same Node?
**Decision**: Germany has PG primary + CH replica

**Rationale**:
- **Separation principle**: Only applies to BOTH PRIMARIES
- Germany: PRIMARY + replica ✅ (allowed)
- Austria: PRIMARY + replica ✅ (allowed)
- Different primaries on different nodes ✅ (required)
- Research confirms this pattern is correct

### Why Primary-Replica Model?
**Decision**: Use primary-replica vs multi-master

**Rationale**:
- **Write volume**: Low (100 writes/min Postgres)
- **ClickHouse**: Batched async writes via ResilientWriter
- **Oban limitation**: Requires single Postgres primary
- **Latency**: Acceptable (150ms amortized to <1ms with batching)
- **Complexity**: Much simpler than multi-master

### Why 14-Month Retention?
**Decision**: 14 months vs 3 months

**Rationale**:
- **Storage**: With compression, only ~120 GB for 10K monitors
- **Fits**: Comfortably in 256 GB Netcup nodes
- **Value**: Year-over-year comparisons for customers
- **Cost**: $0 extra (no S3 needed)

---

## Related Documentation

- [Final 5-Node Architecture](./final-5-node-architecture.md) - Complete specs
- [Why Separate Database Primaries](./why-separate-database-primaries.md) - Design rationale
- [Deployment Guide](../DEPLOYMENT.md) - Step-by-step setup
- [NixOS Setup](../NIXOS-SETUP-COMPLETE.md) - Infrastructure as code

---

## Quick Commands

### Check Cluster Status
```bash
# Patroni cluster
patronictl list uptrack-pg-cluster

# ClickHouse replication
clickhouse-client -q "SELECT * FROM system.replicas"

# etcd health
etcdctl endpoint health --cluster

# Tailscale mesh
tailscale status
```

### Failover Testing
```bash
# Test Postgres failover (automatic)
systemctl stop patroni  # On Germany
patronictl list         # Watch Austria promote

# Test ClickHouse failover (manual)
systemctl stop clickhouse  # On Austria
# Promote Germany manually or via script
```

### Scaling Examples
```bash
# Add Tokyo node
- Provision OVH VPS-1 in Tokyo
- Install Tailscale, Phoenix, Oban
- Configure NODE_REGION=ap-northeast
- Deploy app (no databases needed)

# Upgrade Netcup storage
- Order VPS 2000 ARM G11 (512 GB)
- Migrate data from VPS 1000
- Update configs
- Decommission old node
```

---

**Architecture Status**: ✅ Production Ready
**Next Review**: When approaching 7K monitors or adding 3+ regions
