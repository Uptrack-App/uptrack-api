# Infrastructure Design

## Architecture Overview

### Node Distribution

```
COMPUTE LAYER (Netcup Nuremberg - <5ms inter-node latency)
┌─────────────────────────────────────────────────────────────────────┐
│ nbg-1                        4 vCPU, 8GB RAM, 512GB NVMe            │
│ • etcd (1/3)                 • vminsert                             │
│ • PostgreSQL Primary         • vmselect                             │
│ • Patroni                                                           │
│ Tailscale: 100.64.1.1                                               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ nbg-2                        4 vCPU, 8GB RAM, 512GB NVMe            │
│ • etcd (2/3)                 • vminsert                             │
│ • PostgreSQL Sync Replica    • vmselect                             │
│ • Patroni                                                           │
│ Tailscale: 100.64.1.2                                               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ nbg-3                        4 vCPU, 8GB RAM, 512GB NVMe            │
│ • etcd (3/3)                 • vmselect (backup)                    │
│ • PostgreSQL Async Replica   • vmstorage (HA node 1/2)              │
│ • Patroni                                                           │
│ Tailscale: 100.64.1.3                                               │
└─────────────────────────────────────────────────────────────────────┘

STORAGE LAYER (HostHatch Amsterdam - 5-10ms to Nuremberg)
┌─────────────────────────────────────────────────────────────────────┐
│ storage-1                    2 vCPU, 2GB RAM, 1TB NVMe              │
│ • vmstorage (HA node 2/2)    • -retentionPeriod=15M                 │
│ Tailscale: 100.64.2.1                                               │
│                                                                     │
│ HYBRID HA: nbg-3 + storage-1 with replicationFactor=2               │
└─────────────────────────────────────────────────────────────────────┘

FUTURE STORAGE (Add when 3-node HA needed for higher availability)
┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
  storage-2                    2 vCPU, 2GB RAM, 1TB NVMe
  • vmstorage                  • replicationFactor=2 (any 2 of 3)
  Tailscale: 100.64.2.2
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘

DR LAYER (Oracle Cloud India - 80-120ms to EU)
┌─────────────────────────────────────────────────────────────────────┐
│ india-strong                 3 OCPU, 18GB RAM, 46GB SSD             │
│ • PostgreSQL Async Replica   • vmselect (reads from EU storage)     │
│ • vmagent (local metrics)    • Prometheus (global scraper)          │
│ Tailscale: 100.64.3.1                                               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ india-weak                   1 OCPU, 6GB RAM, ~40GB                 │
│ • Backups (PG WAL + VM)      • Loki (log aggregation)               │
│ • Alertmanager               • Monitoring dashboards                │
│ Tailscale: 100.64.3.2                                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Data Flow

**Metrics Ingestion:**
```
Application → vminsert (nbg-1 or nbg-2) with -replicationFactor=2
              ↓
          Write to BOTH nodes
              ↓
     ┌────────┴────────┐
     ↓                 ↓
vmstorage           vmstorage
(nbg-3)            (storage-1)
  512GB              1TB NVMe
    └────── HA ───────┘
```

**Metrics Queries:**
```
EU Users → vmselect (nbg-1 or nbg-2)
              ↓
          Fan-out to both vmstorage nodes
              ↓
          nbg-3 (<5ms) + storage-1 (5-10ms)
              ↓
          Merge results (dedup with replicationFactor=2)
              ↓
          Return to user

Asia Users → vmselect (india-strong)
                ↓
          Query EU vmstorage (80-120ms)
                ↓
          Return to user
```

**PostgreSQL Writes:**
```
Application → PostgreSQL Primary (nbg-1 via Patroni VIP)
                   ↓
            ┌──────┼──────┐
            ↓      ↓      ↓
     Sync to    Async to   Async to
      nbg-2      nbg-3    india-strong
    (replica)  (replica) (DR replica)
```

## Key Design Decisions

### 1. Why Hybrid vmstorage Architecture (nbg-3 + storage-1)?

**Decision:** Run vmstorage on both nbg-3 (Netcup) and storage-1 (HostHatch) with replicationFactor=2 for HA.

**Rationale:**
- 2-node HA from day one with minimal cost
- Uses existing nbg-3 capacity (512GB NVMe has plenty of headroom)
- Only need 1 additional HostHatch node (~€6/mo) instead of 3 (~€18/mo)
- replicationFactor=2 means data is written to BOTH nodes

**Benefits:**
- ✅ HA from day one: Either node can fail, queries continue
- ✅ Cost efficient: €6/mo vs €18/mo for 3 dedicated storage nodes
- ✅ Uses existing resources: nbg-3 has 512GB NVMe, only ~80GB needed
- ✅ Geographic redundancy: Nuremberg + Amsterdam

**Trade-offs:**
- nbg-3 shares disk with PostgreSQL async replica (monitor usage)
- Asymmetric storage: nbg-3 (512GB) vs storage-1 (1TB)
- Needs both nodes up for writes (acceptable for monitoring workload)

**Capacity Planning:**
- Expected usage: 31GB VM + 50GB PG = ~80GB on nbg-3
- Available on nbg-3: 512GB NVMe → 430GB headroom ✅
- storage-1: 1TB dedicated → plenty for future growth

**Validation (from VictoriaMetrics docs):**
- "vminsert and vmselect nodes are stateless and may be added/removed at any time"
- "vmstorage nodes own the ingested data, so they cannot be removed without data loss"
- replicationFactor=2 with 2 nodes = full replication (data on both)

### 2. Why HostHatch Amsterdam vs Nuremberg?

**Decision:** Use Amsterdam for HostHatch storage nodes.

**Rationale:**
- Geographic redundancy: Different city from compute (Nuremberg)
- Latency: Amsterdam ↔ Nuremberg ~5-10ms (excellent)
- Availability: HostHatch has well-established Amsterdam DC
- Disaster recovery: Survives Nuremberg-specific outages

**Alternative Considered:**
- Nuremberg HostHatch (if available): Lower latency but same failure domain

### 3. Why Tailscale Network Segregation?

**Decision:** Use different Tailscale IP ranges per layer:
- 100.64.1.x: Compute layer (Netcup)
- 100.64.2.x: Storage layer (HostHatch)
- 100.64.3.x: DR layer (Oracle India)

**Rationale:**
- Clear network topology visualization
- Easy firewall rules per layer
- Simplified troubleshooting
- Future: Different ACL policies per layer

### 4. Why etcd Only in Nuremberg (Not HostHatch or India)?

**Decision:** Run etcd 3-node cluster only on Netcup Nuremberg nodes.

**Rationale:**
- etcd requires <50ms latency for stable consensus
- Nuremberg nodes: <5ms ✅
- HostHatch Amsterdam: 5-10ms ✅ (acceptable but unnecessary complexity)
- India nodes: 80-120ms ❌ (causes split-brain)

**Implications:**
- PostgreSQL failover contained within Nuremberg
- India replica follows, cannot auto-promote
- If all Nuremberg nodes fail, manual intervention required

### 5. Why PostgreSQL Witness on nbg-3?

**Decision:** Run PostgreSQL on all 3 Netcup nodes:
- nbg-1: Primary
- nbg-2: Synchronous replica (zero data loss)
- nbg-3: Asynchronous replica (witness for quorum)

**Rationale:**
- 3-node quorum prevents split-brain
- Synchronous replica on nbg-2 ensures zero data loss
- Witness on nbg-3 uses minimal resources
- Automatic failover: nbg-1 down → nbg-2 promoted in <30s

**Alternative Considered:**
- 2-node PostgreSQL: Risky, no quorum
- PostgreSQL on HostHatch: Wrong use case (storage optimized, not OLTP)

### 6. Why vmselect on india-strong?

**Decision:** Deploy vmselect on india-strong for Asian users.

**Rationale:**
- Query routing: Asian users hit local vmselect
- vmselect fans out to EU vmstorage (80-120ms)
- Total latency: 80-120ms + query time vs 160-240ms round-trip
- ~50% latency reduction for Asian users

**Note:** Not running vmstorage in India because:
- Replication latency (80-120ms) would slow writes
- Storage sync complexity
- India is DR, not primary

## Capacity Planning

### Netcup Resource Allocation (vmselect/vminsert on Compute Nodes)

**Decision:** Run vmselect and vminsert on Netcup nodes alongside PostgreSQL. No dedicated VPS needed.

**Why vmselect/vminsert are lightweight:**
- vminsert: Receives metrics, forwards to vmstorage (~200MB RAM)
- vmselect: Queries vmstorage, merges results (~500MB RAM, 1GB peak)
- Both are stateless (no disk needed)

**Netcup G12 (8GB RAM) Resource Breakdown:**
```
┌────────────────────────────────────────────────────┐
│ PostgreSQL + Patroni:    2-3 GB                    │
│ etcd:                    200 MB                    │
│ vminsert:                200 MB                    │
│ vmselect:                500 MB (1GB peak)         │
│ App (Phoenix):           500 MB                    │
│ OS + buffers:            2 GB                      │
│ ─────────────────────────────────────              │
│ Total used:              ~6 GB                     │
│ Headroom:                ~2 GB ✅                  │
└────────────────────────────────────────────────────┘
```

**vmselect scaling (future):**
| Concurrent Queries | vmselect Instances | Action |
|-------------------|-------------------|--------|
| 1-20 | 2 (nbg-1, nbg-2) | ✅ Current setup |
| 20-50 | 3 (add nbg-3) | Enable vmselect on nbg-3 |
| 50+ | Dedicated VPS | Add ~€7/mo compute node |

### VictoriaMetrics Sizing

**Current Workload (10,000 monitors):**
```
Ingestion rate: 10,000 monitors × (1,920 checks/day ÷ 86,400 sec) × 3 metrics
             = 10,000 × 0.022 × 3
             = 666 samples/sec

CPU (vminsert): 666 / 100,000 = 0.007 cores (negligible)
               Actual: 0.5 cores per vminsert for overhead
```

**Storage (15-month retention):**
```
Data points: 666 samples/sec × 86,400 sec/day × 456 days
           = 26.2 billion data points

Storage: 26.2B × 1.2 bytes (VM compression)
       = ~31.5 GB total

With 2 vmstorage nodes (nbg-3 + storage-1, ~1.5TB total): 48x headroom ✅
```

**vmstorage RAM requirements:**
```
Rule: ~1GB RAM per 1 million active time series

Your workload: 10,000 monitors × 3 metrics = 30,000 time series
RAM needed: ~30MB for indexes

2GB vmstorage: Supports up to ~2 million time series (666K monitors)
```

### PostgreSQL Sizing

**Current Workload:**
```
Inserts: 10,000 monitors × 1,920 checks/day
       = 19.2M rows/day
       = 222 inserts/sec

Storage: 19.2M × 365 × 1.25 years × 100 bytes
       = ~800 GB for 15 months

With partitioning + cleanup: ~50 GB active
```

**Netcup 512GB NVMe:** Plenty of headroom for PostgreSQL

### Growth Scenarios

| Scale | Monitors | VM Storage | PG Storage | Action Needed |
|-------|----------|------------|------------|---------------|
| Current | 10,000 | 31 GB | 50 GB | None |
| 3x | 30,000 | 95 GB | 150 GB | None |
| 5x | 50,000 | 160 GB | 250 GB | None |
| 10x | 100,000 | 315 GB | 500 GB | Add vmstorage node |

## Security Architecture

### Network Layers

```
Layer 1: Public Internet
├─ Port 22 (SSH) → Key-only auth, fail2ban
├─ Port 443 (HTTPS) → Application (Caddy)
└─ All other ports: CLOSED

Layer 2: Tailscale VPN
├─ 100.64.1.0/24: Compute (Netcup)
├─ 100.64.2.0/24: Storage (HostHatch)
├─ 100.64.3.0/24: DR (Oracle India)
│
├─ PostgreSQL: 5432 (Tailscale only)
├─ etcd: 2379, 2380 (Tailscale only)
├─ VictoriaMetrics:
│   ├─ vmstorage: 8400 (vminsert), 8401 (vmselect), 8482 (HTTP)
│   ├─ vminsert: 8480
│   └─ vmselect: 8481
├─ Prometheus: 9090
├─ Loki: 3100
└─ Alertmanager: 9093

Layer 3: localhost
└─ Unix sockets for local connections
```

### Firewall Rules (NixOS)

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 443 ];
  trustedInterfaces = [ "tailscale0" ];
};
```

## Disaster Recovery

### Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| Single vmstorage down | Queries slower, no data loss | Auto-heal when node returns |
| Single Netcup node down | PG failover <30s, queries continue | Automatic |
| All HostHatch down | No metrics queries | Restore from backup |
| All Netcup down | PG down, promote India manually | Manual (30 min) |
| Complete EU failure | Promote India, lose recent data | Manual (1-2 hours) |

### RTO/RPO

| Service | RTO | RPO |
|---------|-----|-----|
| PostgreSQL (single node) | 30 seconds | 0 (sync replica) |
| PostgreSQL (region) | 30 minutes | 1-2 seconds (async lag) |
| VictoriaMetrics | 5 minutes | 1 day (backup interval) |

## Cost Analysis

### Monthly Costs (Phased Approach)

**Phase 1: Start with HA (Hybrid vmstorage)**
| Item | Quantity | Unit Cost | Monthly |
|------|----------|-----------|---------|
| Netcup G12 Pro | 3 | ~€7 | €21 |
| HostHatch Storage VPS | 1 | ~$7 | ~€6 |
| Oracle Cloud | 2 | €0 (free tier) | €0 |
| Tailscale | 1 | €0 (free tier) | €0 |
| **Total** | | | **~€27** |

Note: vmstorage HA included from day one (nbg-3 + storage-1 with replicationFactor=2)

**Phase 2: Add Vienna (Geo-redundancy)**
| Item | Change | Monthly |
|------|--------|---------|
| Vienna VPS (PG sync replica) | +1 | +€5 |
| **Total** | | **~€32** |

**Phase 3: Add 3rd vmstorage (Higher Availability)**
| Item | Change | Monthly |
|------|--------|---------|
| HostHatch Storage VPS (storage-2) | +1 | +€6 |
| **Total** | | **~€38** |

Note: With 3 vmstorage nodes, replicationFactor=2 means data survives any 1 node failure

### Cost per Monitor

```
Phase 1: €27/mo ÷ 10,000 monitors = €0.0027/monitor/month
Phase 3: €38/mo ÷ 50,000 monitors = €0.00076/monitor/month
```

### Scaling Costs

| Phase | What | Nodes | Monthly Cost |
|-------|------|-------|--------------|
| 1 (Start) | 3 Netcup + 1 HostHatch (vmstorage HA via nbg-3) | 4 | ~€27 |
| 2 (Geo) | + Vienna PG replica | 5 | ~€32 |
| 3 (VM 3-node) | + 1 HostHatch vmstorage (storage-2) | 6 | ~€38 |
| 4 (Scale) | + Citus workers | 7+ | ~€45+ |

## Success Metrics

**Performance:**
- [ ] Metric ingestion: 666 samples/sec sustained
- [ ] Query latency: <100ms p95 for EU, <200ms p95 for Asia
- [ ] PostgreSQL write: 222 inserts/sec sustained
- [ ] PostgreSQL failover: <30 seconds
- [ ] vmstorage ↔ vminsert latency: <10ms

**Reliability:**
- [ ] Uptime: 99.9% (43 minutes/month downtime budget)
- [ ] Zero data loss events
- [ ] Zero split-brain events
- [ ] Successful failover tested monthly

**Cost:**
- [ ] Monthly cost: <€50/mo
- [ ] Storage utilization: <30% (room for growth)

## Application Architecture: Hybrid OTP + Oban

### Decision: Use Native OTP for High-Frequency, Oban for Persistence

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Monitor scheduling | GenServer | Fast, no DB overhead |
| HTTP checks | Task.async | Parallel, in-memory |
| Store metrics | VictoriaMetrics | Time-series optimized |
| Send alerts | Oban | Must retry, persist |
| Webhooks | Oban | Must retry, persist |
| Daily reports | Oban | Cron scheduling |
| Billing sync | Oban | Must not lose |

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     UPTRACK ARCHITECTURE                     │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            NATIVE OTP (Fast, No Overhead)           │    │
│  │                                                     │    │
│  │  MonitorScheduler (GenServer)                       │    │
│  │       │                                             │    │
│  │       ▼ every 30 sec                                │    │
│  │  TaskSupervisor ──▶ Task ──▶ Task ──▶ Task         │    │
│  │       │              │        │        │            │    │
│  │       │         HTTP checks (parallel)              │    │
│  │       │              │        │        │            │    │
│  │       ▼              ▼        ▼        ▼            │    │
│  │  VictoriaMetrics (metrics)                          │    │
│  └─────────────────────────────────────────────────────┘    │
│                          │                                   │
│                          │ Only if alert needed              │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              OBAN (Persistent, Retries)             │    │
│  │                                                     │    │
│  │  • SendAlert (notifications)                        │    │
│  │  • ProcessWebhook (external integrations)           │    │
│  │  • DailyReport (scheduled)                          │    │
│  │  • BillingSync (must not lose)                      │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Why Hybrid Approach

| Concern | Native OTP | Oban | Winner |
|---------|------------|------|--------|
| Overhead per job | ~0ms | ~5-10ms (DB) | OTP for high-freq |
| Persistence | ❌ | ✅ | Oban for critical |
| Retries | Manual | Built-in | Oban for external calls |
| Survives restart | ❌ | ✅ | Oban for must-complete |
| Scheduling | Manual | Cron plugin | Oban for scheduled |

### Monitor Check Flow (30-second interval)

```elixir
# 1. GenServer schedules checks (no Oban overhead)
MonitorScheduler
    │
    ▼
# 2. Tasks run HTTP checks in parallel
TaskSupervisor.async_stream(monitors, &check/1)
    │
    ▼
# 3. Results go directly to VictoriaMetrics
VictoriaMetrics.write(metrics)
    │
    ▼
# 4. ONLY if alert needed, use Oban
if alert_needed do
  Oban.insert(SendAlert.new(%{monitor_id: id}))
end
```

## Oban + Citus Coexistence

### How They Work Together

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CITUS COORDINATOR                                │
│                                                                          │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐   │
│  │     "oban" SCHEMA           │  │     "public" SCHEMA              │   │
│  │     (LOCAL - not sharded)   │  │     (DISTRIBUTED)                │   │
│  │                             │  │                                  │   │
│  │  • oban_jobs                │  │  • organizations ──┐             │   │
│  │  • oban_peers               │  │  • users ──────────┼── Sharded   │   │
│  │  • oban_producers           │  │  • monitors ───────┘             │   │
│  │                             │  │                                  │   │
│  │  Never leaves coordinator   │  │  Distributed to workers          │   │
│  └─────────────────────────────┘  └─────────────┬────────────────────┘   │
│                                                  │                        │
└──────────────────────────────────────────────────┼────────────────────────┘
                                                   │
                                    ┌──────────────┴──────────────┐
                                    ▼                             ▼
                           ┌──────────────┐              ┌──────────────┐
                           │   Worker 1   │              │   Worker 2   │
                           └──────────────┘              └──────────────┘
```

### Migration Strategy

```elixir
# Single migration file works for both Oban + Citus
defmodule MyApp.Repo.Migrations.SetupDatabase do
  use Ecto.Migration

  def up do
    # 1. OBAN (stays LOCAL - don't distribute)
    Oban.Migrations.up(version: 12, prefix: "oban")

    # 2. APP TABLES
    create table(:organizations) do
      add :name, :string, null: false
      timestamps()
    end

    create table(:monitors) do
      add :organization_id, references(:organizations), null: false
      add :url, :string, null: false
      timestamps()
    end

    # 3. DISTRIBUTE only app tables (NOT Oban)
    execute "SELECT create_distributed_table('organizations', 'id')"
    execute "SELECT create_distributed_table('monitors', 'organization_id')"
  end

  def down do
    execute "SELECT undistribute_table('monitors')"
    execute "SELECT undistribute_table('organizations')"
    drop table(:monitors)
    drop table(:organizations)
    Oban.Migrations.down(prefix: "oban")
  end
end
```

### Oban Config for Citus

```elixir
# config/config.exs
config :my_app, Oban,
  repo: MyApp.Repo,
  prefix: "oban",                 # Separate schema (stays local)
  notifier: Oban.Notifiers.PG,    # Erlang PG for distributed nodes
  queues: [
    default: 10,
    notifications: 5,
    webhooks: 3
  ]
```

### Key Rules

| Table Type | Command | Location |
|------------|---------|----------|
| Oban tables | `Oban.Migrations.up()` | LOCAL (coordinator only) |
| App tables | `create_distributed_table()` | DISTRIBUTED (workers) |
| Default | `CREATE TABLE` | LOCAL (unless distributed) |

## Geographic Rollout Strategy

### Phase 1: Start with 3 Nuremberg (Now)

```
Nuremberg (Same DC - Still HA)
┌─────────────┬─────────────┬─────────────┐
│   nbg-1     │   nbg-2     │   nbg-3     │
│  Primary    │   Sync      │   Async     │
│  etcd 1/3   │  etcd 2/3   │  etcd 3/3   │
└─────────────┴─────────────┴─────────────┘

✅ Single node failure → Auto-failover
✅ PostgreSQL HA within DC
✅ Fast sync replication (<5ms)
✅ WAL archiving to Backblaze B2
❌ No geo-redundancy (acceptable risk for now)

Cost: €21/mo (3 × €7 Netcup)
```

**DR Strategy:**
- WAL continuous archiving to Backblaze B2
- If Nuremberg DC fails → restore from B2 (~30 min RTO)

### Phase 2: Add Vienna Sync Replica Later (Planned)

**Decision:** Add Vienna as SYNC replica for zero data loss geo-redundancy.

```
Nuremberg (Primary)              Vienna (Sync Replica)
┌─────────┬─────────┬─────────┐  ┌─────────────────┐
│  nbg-1  │  nbg-2  │  nbg-3  │  │   vienna-1      │
│ Primary │  Sync   │ Async   │══│  SYNC replica   │
│ etcd 1/3│ etcd 2/3│ etcd 3/3│  │  (no etcd)      │
└─────────┴─────────┴─────────┘  └─────────────────┘
         <5ms                      10-15ms

✅ Geo-redundancy
✅ ZERO data loss (synchronous replication)
✅ If Nuremberg fails → promote Vienna (~5 min RTO)
⚠️  Write latency: +10-15ms (acceptable for monitoring app)

Cost: €26/mo (+€5 for Vienna VPS)
```

**Sync vs Async for Vienna:**
| Mode | Data Loss Risk | Write Latency | Decision |
|------|----------------|---------------|----------|
| Async | 0-5 sec if DC fails | ~1ms | ❌ Not chosen |
| Sync | Zero | +10-15ms | ✅ Chosen |

**Why Sync:** Billing and user data must never be lost. 10-15ms write latency is acceptable for a monitoring app (not a trading platform).

**Options for Vienna:**
| Provider | Plan | Specs | Price |
|----------|------|-------|-------|
| Netcup | VPS 1000 | 2 CPU, 4GB, 128GB | €4.99/mo |
| Hetzner | CX22 | 2 CPU, 4GB, 40GB | €3.99/mo |
| Contabo | VPS S | 4 CPU, 8GB, 200GB | €5.99/mo |

### Migration Path: Adding Vienna (Zero Downtime, Zero Data Loss)

When ready to add Vienna:

1. **Purchase Vienna VPS** (~€5/mo)
2. **Install NixOS + Tailscale** (100.64.1.4)
3. **Take base backup** (no downtime): `pg_basebackup -h nbg-1 -D /var/lib/postgresql -P -R`
4. **Start streaming replication** (starts as async automatically)
5. **Wait for replica to catch up** (monitor: `pg_stat_replication`)
6. **Switch to sync mode** on primary:
   ```sql
   ALTER SYSTEM SET synchronous_standby_names = 'vienna-1';
   SELECT pg_reload_conf();
   ```
7. **Update DR runbook** (manual promotion procedure)

**Guarantees:**
- ✅ Zero downtime during setup
- ✅ Zero data loss during migration
- ✅ Zero data loss after sync enabled
- ✅ Can be done anytime in the future

### Future: Relocate nbg-3 to Vienna (Optional)

If Netcup allows relocation later:

```
Before:                          After:
nbg-1, nbg-2, nbg-3             nbg-1, nbg-2, vienna-1
(all Nuremberg)                 (2 Nuremberg + 1 Vienna)
```

Relocation steps:
1. Add new Vienna node as replica
2. Remove nbg-3 from etcd cluster
3. Add vienna-1 to etcd cluster
4. Decommission nbg-3
5. Reassign Tailscale IP (100.64.1.3 → vienna-1)

## Summary: Phased Infrastructure Rollout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    INFRASTRUCTURE PHASES                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PHASE 1: START WITH HA (~€27/mo)                                      │
│  ├─ 3× Netcup G12 (Nuremberg): PostgreSQL HA + etcd + vminsert/vmselect│
│  ├─ 1× HostHatch 2GB (Amsterdam): vmstorage                            │
│  ├─ 2× Oracle Cloud (India): Free tier DR                              │
│  ├─ PostgreSQL: HA within Nuremberg                                    │
│  ├─ VictoriaMetrics: Hybrid HA (nbg-3 + storage-1, replicationFactor=2)│
│  └─ Capacity: 10K-100K monitors                                        │
│                                                                         │
│  PHASE 2: GEO-REDUNDANCY (~€32/mo)                                     │
│  ├─ + 1× Vienna VPS (€5/mo): PostgreSQL SYNC replica                   │
│  ├─ PostgreSQL: Zero data loss geo-redundancy                          │
│  ├─ Failover: Nuremberg DC fails → promote Vienna (~5 min)             │
│  └─ Migration: Zero downtime, zero data loss                           │
│                                                                         │
│  PHASE 3: 3-NODE VMSTORAGE (~€38/mo)                                   │
│  ├─ + 1× HostHatch 2GB: storage-2 (3rd vmstorage node)                 │
│  ├─ VictoriaMetrics: 3 nodes, any 1 can fail with RF=2                 │
│  ├─ Metrics: Higher HA, survives 1 node failure during writes          │
│  └─ Capacity: 100K-500K monitors                                       │
│                                                                         │
│  PHASE 4: SCALE WRITES (~€45+/mo)                                      │
│  ├─ + Citus workers: Horizontal PostgreSQL sharding                    │
│  ├─ When: >10K writes/sec (300K+ monitors)                             │
│  └─ Capacity: 1M+ monitors                                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Phase Triggers

| Phase | Trigger | Action |
|-------|---------|--------|
| 1 → 2 | Want geo-redundancy | Buy Vienna VPS, setup sync replica |
| 2 → 3 | Want 3-node vmstorage | Buy 1 more HostHatch (storage-2) |
| 3 → 4 | >10K PG writes/sec | Add Citus workers |

### What's HA at Each Phase

| Phase | PostgreSQL HA | VictoriaMetrics HA | Geo-Redundancy |
|-------|---------------|-------------------|----------------|
| 1 | ✅ Within Nuremberg | ✅ 2-node hybrid (nbg-3 + storage-1) | ❌ No |
| 2 | ✅ + Vienna sync | ✅ 2-node hybrid | ✅ Yes |
| 3 | ✅ + Vienna sync | ✅ 3 nodes (nbg-3 + storage-1 + storage-2) | ✅ Yes |
| 4 | ✅ + Citus sharding | ✅ 3 nodes | ✅ Yes |
