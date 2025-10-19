# Uptrack Final 5-Node Architecture

**Status**: Recommended
**Updated**: 2025-10-19
**Total Cost**: ~$23/month
**Coverage**: 3 continents, 14-month retention
**Scale**: Supports up to 10K monitors

---

## 🎯 Architecture Overview

### Core Principle: Separate Primary Databases

**Key Design Decision**: PostgreSQL PRIMARY and ClickHouse PRIMARY run on **different nodes** to eliminate single point of failure and maintain observability during incidents.

```
PostgreSQL PRIMARY: Germany 🇩🇪
ClickHouse PRIMARY: Austria 🇦🇹
✅ Different nodes (follows separation principle)
✅ Both in EU (low latency between them: ~20-30ms)
```

---

## 📊 Node Specifications

| Node | Location | Provider | vCore | RAM | Storage | Role | Cost/mo |
|------|----------|----------|-------|-----|---------|------|---------|
| **Germany** | Nuremberg/Vienna | Netcup ARM G11 | 6 ARM | 8 GB | 256 GB | PG Primary + CH Replica | $7.11 |
| **Austria** | Nuremberg/Vienna | Netcup ARM G11 | 6 ARM | 8 GB | 256 GB | CH Primary + PG Replica | $7.11 |
| **Canada** | - | OVH VPS-1 | 4 | 8 GB | 75 GB | App-only | $4.20 |
| **India Strong** | Hyderabad | Oracle Free | ? | ? | 145 GB | PG Replica | Free |
| **India Weak** | Hyderabad | Oracle Free | 1 | ? | ? | App-only + etcd | Free |

**Total Monthly Cost**: ~$18.42 + tax = **~$23/month**

---

## 🗄️ Database Distribution

### PostgreSQL Cluster (Patroni 3-node HA)

```
┌─────────────────────────────────────────────┐
│ PRIMARY: Germany 🇩🇪 (Netcup 256 GB)        │
│ • Handles all transactional writes          │
│ • User actions, monitor configs, incidents  │
│ • Patroni leader                            │
└─────────────────────────────────────────────┘
          ↓ streaming replication
    ┌─────────┴─────────┐
    ↓                   ↓
Austria 🇦🇹         India Strong 🇮🇳
(Replica)           (Replica)
```

**Patroni Configuration:**
- **Scope**: `uptrack-pg-cluster`
- **Quorum**: 2/3 nodes
- **Automatic failover**: 30 seconds
- **Replication lag target**: <100ms

### ClickHouse Cluster (2-node replication)

```
┌─────────────────────────────────────────────┐
│ PRIMARY: Austria 🇦🇹 (Netcup 256 GB)        │
│ • 14-month retention (~120 GB)              │
│ • Handles all monitoring data writes        │
│ • ZSTD compression (15x)                    │
└─────────────────────────────────────────────┘
          ↓ replication
          ↓
    Germany 🇩🇪
    (Replica, 14-month)
```

**Why only 2 nodes?**
- India Strong: Limited to Postgres replica only (145 GB constraint)
- 2 nodes sufficient with ResilientWriter disk spooling
- Can add India replica when upgraded storage

### etcd Cluster (5-node consensus)

**Members:**
1. Germany 🇩🇪
2. Austria 🇦🇹
3. Canada 🇨🇦
4. India Strong 🇮🇳
5. India Weak 🇮🇳

**Configuration:**
- **Quorum**: 3/5 nodes
- **Failure tolerance**: 2 nodes
- **Why 5?**: Odd number (optimal for consensus)
- **Geographic spread**: EU (2), North America (1), APAC (2)

---

## 💾 Storage Allocation

| Node | PostgreSQL | ClickHouse | System | Total | Capacity | Utilization |
|------|-----------|------------|--------|-------|----------|-------------|
| **Germany** | 40 GB (primary) | 120 GB (replica) | 15 GB | **175 GB** | 256 GB | **68%** ✅ |
| **Austria** | 40 GB (replica) | 120 GB (primary) | 15 GB | **175 GB** | 256 GB | **68%** ✅ |
| **Canada** | 0 GB | 0 GB | 15 GB | **15 GB** | 75 GB | **20%** ✅ |
| **India Strong** | 40 GB (replica) | 0 GB | 15 GB | **55 GB** | 145 GB | **38%** ✅ |
| **India Weak** | 0 GB | 0 GB | 15 GB | **15 GB** | ? | ✅ |

**Notes:**
- ClickHouse 120 GB = 14-month retention for 10K monitors
- PostgreSQL 40 GB = transactional data (users, monitors, incidents)
- All nodes have comfortable headroom for growth

---

## 🌍 Regional Coverage & Network Topology

### Geographic Distribution

| Region | Nodes | Primary Role | Latency to Users |
|--------|-------|--------------|------------------|
| **Europe** | Germany, Austria | Database primaries + apps | <30ms |
| **North America** | Canada | App-only | <50ms |
| **APAC** | India Strong, India Weak | Postgres replica + apps | <100ms |

### Network Connections (Tailscale Private Network)

```
All nodes connected via Tailscale mesh:
├─ Germany: 100.64.0.1
├─ Austria: 100.64.0.2
├─ Canada: 100.64.0.3
├─ India Strong: 100.64.0.4
└─ India Weak: 100.64.0.5

Database Access:
├─ Apps → Postgres PRIMARY: germany:5432 (via HAProxy)
├─ Apps → ClickHouse PRIMARY: austria:8123
└─ Reads → Local replicas when available
```

---

## 🚀 Application Services (All Nodes)

### Phoenix App + Oban Workers

**All 5 nodes run:**
- Phoenix web application (port 4000)
- Oban job workers (regional monitoring checks)
- HAProxy (HTTPS termination, DB routing)

**Configuration per node:**

```elixir
# Germany
config :uptrack,
  node_region: "eu-central",
  postgres_primary: "100.64.0.1:5432",
  postgres_replica: "100.64.0.1:5432",  # Local
  clickhouse_primary: "100.64.0.2:8123"

# Austria
config :uptrack,
  node_region: "eu-central",
  postgres_primary: "100.64.0.1:5432",
  postgres_replica: "100.64.0.2:5432",  # Local
  clickhouse_primary: "100.64.0.2:8123"  # Local

# Canada (app-only, no local DBs)
config :uptrack,
  node_region: "us-east",
  postgres_primary: "100.64.0.1:5432",
  postgres_replica: "100.64.0.1:5432",  # Use Germany
  clickhouse_primary: "100.64.0.2:8123"

# India Strong (has Postgres replica)
config :uptrack,
  node_region: "ap-south",
  postgres_primary: "100.64.0.1:5432",
  postgres_replica: "100.64.0.4:5432",  # Local
  clickhouse_primary: "100.64.0.2:8123"

# India Weak (app-only, no local DBs)
config :uptrack,
  node_region: "ap-south",
  postgres_primary: "100.64.0.1:5432",
  postgres_replica: "100.64.0.4:5432",  # Use India Strong
  clickhouse_primary: "100.64.0.2:8123"
```

---

## 🔄 High Availability & Failover

### PostgreSQL Failover (Automatic via Patroni)

**Scenario 1: Germany dies (Postgres primary)**
```
03:00:00 - Germany node fails
03:00:01 - Patroni detects leader loss
03:00:05 - etcd votes on new leader (Austria or India)
03:00:30 - Patroni promotes Austria to primary
03:00:31 - HAProxy routes to new primary
Total RTO: 30 seconds ✅
User impact: Brief write delay, reads unaffected
```

**Scenario 2: Austria or India replica dies**
```
Impact: None (primary Germany still running)
RTO: 0 seconds ✅
```

### ClickHouse Failover (Manual or scripted)

**Scenario 1: Austria dies (ClickHouse primary)**
```
03:00:00 - Austria node fails
03:00:00 - ClickHouse writes fail
03:00:00 - ResilientWriter spools to disk on all app nodes
03:00:05 - Alert sent to ops team
03:05:00 - Promote Germany to primary (manual/script)
03:05:30 - Update app configs, restart apps
03:06:00 - Spool flush begins
Total RTO: 5-6 minutes ⚠️
User impact: Monitoring data spooled, no data loss
```

**Scenario 2: Germany replica dies**
```
Impact: None (primary Austria still running)
RTO: 0 seconds ✅
Note: Lose redundancy until Germany restored
```

### App Node Failover (Instant via Cloudflare)

**Scenario: Any app node dies**
```
00:00:00 - Node fails
00:00:01 - Cloudflare health check detects failure
00:00:02 - Cloudflare removes from DNS rotation
00:00:03 - Traffic routed to remaining 4 nodes
Total RTO: <5 seconds ✅
User impact: None (automatic)
```

---

## 📈 Scaling Strategy

### Current Capacity (5 nodes)

| Metric | Current Support | Bottleneck |
|--------|----------------|------------|
| **Monitors** | Up to 10K | ClickHouse storage (120 GB) |
| **Checks/minute** | 30K (10K × 3 regions) | Oban workers |
| **Concurrent users** | 1000+ | Phoenix connections |
| **Data retention** | 14 months | ClickHouse storage |

### Scaling Options

#### Option 1: Add Regional App Nodes (Easy, $4-5/node/month)

**When**: Need more monitoring regions (Tokyo, Singapore, São Paulo)

```
Add Tokyo node:
├─ OVH VPS-1: 4 vCore, 8 GB, 75 GB
├─ Phoenix app + Oban workers
├─ Connect to Germany/Austria databases (via Tailscale)
├─ NO databases, NO etcd
└─ Cost: +$4.20/month
```

**Benefits:**
- ✅ Improves regional check latency
- ✅ Distributes Oban worker load
- ✅ Increases geographic redundancy
- ✅ Minimal cost increase

**Limitations:**
- ⚠️ Database writes still remote (150-200ms)
- ⚠️ But mitigated by ResilientWriter batching

#### Option 2: Upgrade to Larger Netcup Nodes (Medium, $10-15/month)

**When**: Approaching 10K monitors or 120 GB ClickHouse storage

```
Upgrade Germany/Austria:
├─ From: VPS 1000 ARM G11 (256 GB)
├─ To: VPS 2000 ARM G11 (512 GB) - ~$14/month each
└─ Supports: 20K monitors, 28-month retention
```

#### Option 3: Add ClickHouse Sharding (Complex, $20-30/month)

**When**: Exceeding 20K monitors or need sub-region sharding

```
Shard ClickHouse by region:
├─ Shard 1 (EU data): Austria + Germany
├─ Shard 2 (APAC data): India Strong + Singapore (new)
├─ Shard 3 (NA data): Canada (upgrade) + US East (new)
└─ Use ClickHouse Distributed tables for queries
```

---

## 💰 Cost Breakdown & Projections

### Current Setup (5 nodes)

| Item | Quantity | Unit Cost | Total |
|------|----------|-----------|-------|
| Netcup ARM G11 | 2 | $7.11/mo | $14.22 |
| OVH VPS-1 | 1 | $4.20/mo | $4.20 |
| Oracle Cloud Free Tier | 2 | $0.00 | $0.00 |
| **Subtotal** | | | **$18.42** |
| **With tax (~20%)** | | | **~$23/month** |
| **Annual** | | | **~$276/year** |

### Scaling Cost Projections

| Scenario | Monitors | Nodes | Monthly Cost | Notes |
|----------|----------|-------|--------------|-------|
| **Current** | 1K-10K | 5 | **$23** | Production-ready |
| **Add 3 regions** | 10K | 8 | **$36** | Tokyo, Singapore, São Paulo |
| **Scale to 20K** | 20K | 5 | **$31** | Upgrade Netcup to 512 GB |
| **Scale to 50K** | 50K | 10+ | **$80-120** | Distributed ClickHouse cluster |

---

## ✅ Why This Architecture is Optimal

### 1. Follows Separation Principle
- ✅ PostgreSQL PRIMARY (Germany) ≠ ClickHouse PRIMARY (Austria)
- ✅ Different nodes eliminate single point of failure
- ✅ Maintains observability during incidents

### 2. Storage Optimized
- ✅ 256 GB Netcup nodes hold both databases comfortably (68% utilization)
- ✅ 14-month retention for up to 10K monitors
- ✅ No need for expensive S3 or managed services

### 3. Cost Effective
- ✅ $27/month for production HA across 3 continents
- ✅ vs $200+/month for AWS RDS Multi-AZ + ClickHouse Cloud
- ✅ 7-10x cheaper than managed alternatives

### 4. Geographic Coverage
- ✅ EU (2 nodes): Germany, Austria
- ✅ North America (1 node): Canada
- ✅ APAC (2 nodes): India Strong, India Weak
- ✅ Easy to add more regions (app-only nodes)

### 5. High Availability
- ✅ PostgreSQL: Automatic failover (30s RTO)
- ✅ ClickHouse: Manual failover with disk spooling (no data loss)
- ✅ App: Instant failover via Cloudflare (5s RTO)
- ✅ etcd: Tolerates 2 node failures

### 6. Future-Proof
- ✅ Can scale to 20K monitors with storage upgrade
- ✅ Can add regional nodes for $4-5/month each
- ✅ Can shard ClickHouse when needed
- ✅ Clean upgrade path to distributed setup

---

## 📋 Deployment Checklist

### Phase 1: Provision Nodes

- [ ] Order 2× Netcup VPS 1000 ARM G11 (Germany + Austria)
- [ ] Order 1× OVH VPS-1 (Canada)
- [ ] Setup 2× Oracle Cloud Free Tier (India Strong + Weak)
- [ ] Note down all public IPs

### Phase 2: Network Setup

- [ ] Install Tailscale on all 5 nodes
- [ ] Verify Tailscale mesh (each node can ping others)
- [ ] Note down Tailscale IPs (100.64.0.x)
- [ ] Setup Cloudflare DNS (5 A records, all proxied)

### Phase 3: Database Setup

- [ ] Install PostgreSQL 16 + Patroni on: Germany, Austria, India Strong
- [ ] Install etcd on: Germany, Austria, Canada, India Strong, India Weak
- [ ] Install ClickHouse on: Germany, Austria
- [ ] Verify Patroni cluster (`patronictl list`)
- [ ] Verify ClickHouse replication (`SELECT * FROM system.replicas`)

### Phase 4: Application Deployment

- [ ] Deploy Phoenix app to all 5 nodes
- [ ] Configure Oban with regional queues
- [ ] Setup HAProxy on all nodes
- [ ] Configure SSL certificates (Let's Encrypt)
- [ ] Setup monitoring (health checks, metrics)

### Phase 5: Verification

- [ ] Test Postgres failover (stop Patroni on Germany)
- [ ] Test ClickHouse writes from all regions
- [ ] Test app access from all regions
- [ ] Verify etcd quorum (stop 1 node, cluster still works)
- [ ] Load test with 1000 monitors × 3 regions

---

## 🆘 Troubleshooting

### Postgres Not Failing Over

```bash
# Check etcd cluster health
etcdctl endpoint health --cluster

# Check Patroni status
patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster

# View Patroni logs
journalctl -u patroni -f
```

### ClickHouse Writes Failing

```bash
# Check ResilientWriter spool
ls -lh /var/lib/uptrack/spool/

# Manually flush spool
systemctl start clickhouse-spool-flush.service

# Check ClickHouse logs
journalctl -u clickhouse -f
```

### High Latency from India

```bash
# Check Tailscale connection type (should be "direct")
tailscale ping germany-node

# If using DERP relay, force direct connection
tailscale up --accept-routes --advertise-routes=100.64.0.5/32
```

---

## 📚 Related Documentation

- [Why Separate Database Primaries](./why-separate-database-primaries.md)
- [Deployment Guide](../DEPLOYMENT.md)
- [NixOS Setup](../NIXOS-SETUP-COMPLETE.md)
- [Patroni Configuration](../deploy/patroni/README.md)

---

**Last Updated**: 2025-10-19
**Document Version**: 1.0
**Status**: Production Ready
