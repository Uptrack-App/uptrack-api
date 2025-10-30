# Infrastructure Design

## Architecture Overview

### Node Distribution

```
EU Cluster (Low Latency: <20ms)
┌─────────────────────────────────────────────────────────┐
│ eu-a (Italy/Austria)        4 vCPU, 8GB RAM, 120GB NVMe │
│ • etcd (1/3)                • vmstorage1                 │
│ • PostgreSQL Primary        • vminsert1                  │
│ Tailscale: 100.64.1.1                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ eu-b (Italy/Austria)        4 vCPU, 8GB RAM, 120GB NVMe │
│ • etcd (2/3)                • vmstorage2                 │
│ • PostgreSQL Replica        • vmselect1                  │
│ Tailscale: 100.64.1.2                                    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ eu-c (Italy/Austria)        4 vCPU, 8GB RAM, 120GB NVMe │
│ • etcd (3/3)                • vmstorage3                 │
│ • PostgreSQL Witness        • vminsert2 + vmselect2     │
│ Tailscale: 100.64.1.3                                    │
└─────────────────────────────────────────────────────────┘

Asia Region (High Latency: ~150ms from EU)
┌─────────────────────────────────────────────────────────┐
│ india-s (Oracle Cloud)      3 vCPU, 18GB RAM, 46GB SSD  │
│ • PostgreSQL Async Replica  • vmselect3                  │
│ • Prometheus (global)                                    │
│ Tailscale: 100.64.1.10                                   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ india-w (Oracle Cloud)      1 vCPU, 6GB RAM, ~40GB      │
│ • Backups (PG + VM)         • Loki                       │
│ • Alertmanager                                           │
│ Tailscale: 100.64.1.11                                   │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

**Metrics Ingestion:**
```
Application → vminsert (eu-a or eu-c)
              ↓
          Consistent hashing
              ↓
     ┌────────┼────────┐
     ↓        ↓        ↓
vmstorage1 vmstorage2 vmstorage3
 (eu-a)     (eu-b)     (eu-c)
```

**Metrics Queries:**
```
User (Europe) → vmselect (eu-b or eu-c)
                   ↓
          Fan-out to all vmstorage
                   ↓
              Merge results
                   ↓
             Return to user

User (Asia) → vmselect (india-s)
                 ↓
         Query EU vmstorage (150ms latency)
                 ↓
            Return to user
```

**PostgreSQL Writes:**
```
Application → PostgreSQL Primary (eu-a via Patroni VIP)
                   ↓
            ┌──────┼──────┐
            ↓      ↓      ↓
     Sync to    Sync to    Async to
      eu-b       eu-c     india-s
    (replica)  (witness)  (read replica)
```

**PostgreSQL Reads:**
```
EU Users → Primary (eu-a) or Replica (eu-b)
           ↓
    Read committed data

Asia Users → india-s (async replica)
              ↓
    Read data with ~1-2 second lag (acceptable)
```

## Key Design Decisions

### 1. Why Tailscale Over Public IPs?

**Decision:** Use Tailscale mesh network for all inter-node communication.

**Alternatives Considered:**
- Public IP with firewall rules: 140+ rules, unencrypted, error-prone
- VPN (OpenVPN/IPsec): Complex setup, manual key management
- Cloud provider private networks: Doesn't work across providers (Hostkey + Oracle)

**Rationale:**
- ✅ Zero-trust security (WireGuard encryption)
- ✅ No firewall rules to manage
- ✅ Works across providers (Hostkey, Netcup, Oracle)
- ✅ Easy to add/remove nodes
- ✅ Free tier supports 100 devices
- ✅ 1-3ms latency overhead (negligible)

**Trade-offs:**
- Depends on Tailscale service (99.9% uptime SLA)
- Adds dependency on external service

**Mitigation:**
- Fallback to direct IP if Tailscale fails (documented in runbook)
- Critical services (HTTPS) exposed on public IP as backup

### 2. Why etcd Only in EU (Not India)?

**Decision:** Run etcd 3-node cluster in EU only, exclude India nodes.

**Rationale:**
- etcd requires <50ms latency for stable consensus
- EU nodes: <20ms ✅
- India nodes: 150ms ❌ (causes split-brain)
- PostgreSQL failover must be fast (<30 seconds)

**Implications:**
- India nodes cannot become PostgreSQL primary automatically
- India replica follows EU primary (async, 150ms lag)
- If all EU nodes fail, manual promotion required

**Alternative Considered:**
- 5-node etcd (3 EU + 2 India): Rejected due to latency instability

### 3. Why Co-locate Services on Nodes?

**Decision:** Run multiple services per node (e.g., eu-a has etcd + PostgreSQL + vmstorage + vminsert).

**Alternatives Considered:**
- Dedicated nodes per service (3 for etcd, 3 for PostgreSQL, 3 for VM): 9 nodes total
- Kubernetes with pod scheduling: Overhead too high for 5 nodes

**Rationale:**
- Cost optimization: 5 nodes @ $5.23/mo = $26.15/mo vs 9 nodes @ $47/mo
- Resource utilization: 4 vCPU + 8GB RAM sufficient for multiple services
- Simplicity: Fewer nodes to manage
- Performance: Local communication faster (no network hop)

**Trade-offs:**
- Less isolation (one service can affect others)
- More complex failure scenarios

**Mitigation:**
- Resource limits via systemd (CPU/memory quotas)
- Monitoring per service (separate Prometheus metrics)
- Documented failure scenarios (runbook)

### 4. Why VictoriaMetrics Over Prometheus for Storage?

**Decision:** Use VictoriaMetrics cluster for long-term metrics storage (15 months).

**Alternatives Considered:**
- Prometheus with remote storage: More moving parts
- InfluxDB: Less efficient compression
- TimescaleDB: PostgreSQL extension, more complex queries

**Rationale:**
- ✅ Superior compression (0.5-2 bytes per data point vs Prometheus 3-4 bytes)
- ✅ 15-month retention costs ~35GB vs ~150GB (Prometheus)
- ✅ Better query performance for long time ranges
- ✅ Prometheus-compatible API (easy migration)
- ✅ Horizontal scaling (add vmstorage nodes)

**Trade-offs:**
- Learning curve (different from Prometheus)
- Fewer integrations than Prometheus

### 5. Why 3 vmstorage Nodes (Not 2 or 4)?

**Decision:** Start with 3 vmstorage nodes, scale to 4-6 as needed.

**Rationale:**
- **Storage capacity:** 3 nodes × 120GB = 360GB total, need ~105GB for 15 months
- **Redundancy:** Lose 1 node, cluster still operational (2/3 quorum not needed for VM)
- **Performance:** 3 nodes distribute load well for 10,000 monitors
- **Cost:** 3 nodes = optimal for current scale

**Scaling triggers:**
- 30,000 monitors (3x growth): Add 1 vmstorage (4 total)
- 50,000 monitors (5x growth): Add 3 vmstorage (6 total)
- Storage >80% full: Add nodes proactively

### 6. Why Generic Node Names (eu-a, india-s)?

**Decision:** Use provider-agnostic names instead of provider-specific (hostkey1, oracle1).

**Rationale:**
- ✅ Easy migration: Swap Hostkey → Netcup without config changes
- ✅ Portable configs: `vmstorage = ["100.64.1.1", ...]` stays same
- ✅ Mental model: "eu-a is primary" regardless of provider

**Implementation:**
- Tailscale hostnames: `eu-a`, `eu-b`, `eu-c`, `india-s`, `india-w`
- Tailscale IPs: Fixed (100.64.1.1-3, 100.64.1.10-11)
- Physical location/provider: Metadata only (not in code)

### 7. Why Patroni Over Manual Replication?

**Decision:** Use Patroni for automatic PostgreSQL failover.

**Alternatives Considered:**
- Manual failover: 5-60 minutes downtime, requires on-call
- repmgr: Less mature than Patroni, fewer features

**Rationale:**
- ✅ Automatic failover in 10-30 seconds (vs hours manual)
- ✅ No human intervention needed (sleep peacefully)
- ✅ Prevents split-brain (etcd consensus)
- ✅ Battle-tested (used by major companies)

**Cost:**
- +500MB RAM per node for etcd/Patroni
- +0.3 vCPU per node
- +1-2GB disk for etcd data

**ROI:**
- 99% reduction in downtime (hours → seconds)
- $0 additional monthly cost (software is free)
- Peace of mind: Priceless

### 8. Why PostgreSQL on Same Nodes as VictoriaMetrics?

**Decision:** Co-locate PostgreSQL + VictoriaMetrics on EU nodes.

**Rationale:**
- Different I/O patterns: PostgreSQL (random writes), VM (sequential writes)
- Different workloads: PostgreSQL (OLTP), VM (time-series)
- Resource usage: PostgreSQL peaks during insert, VM is steady
- Cost: No extra nodes needed

**Monitoring:**
- Separate Prometheus metrics for PG and VM
- Alert if one service affects the other (CPU throttling, disk I/O wait)

## Capacity Planning

### Current Workload (100 users × 100 monitors)

**VictoriaMetrics:**
- Data points: 10,000 monitors × 1,920 checks/day × 3 metrics = 57.6M points/day
- 15-month retention: 57.6M × 456 days = 26.2B data points
- Storage: 26.2B × 1.2 bytes = ~31.5GB (with compression)
- Per node: 31.5GB ÷ 3 = ~11GB per vmstorage

**PostgreSQL:**
- Check results: 10,000 monitors × 1,920 checks/day = 19.2M rows/day
- Application data: Users, monitors, incidents, alerts (~1GB)
- Total: ~20GB for 15 months (with partitioning)

**Node utilization (current):**
| Node | CPU | RAM | Disk | Headroom |
|------|-----|-----|------|----------|
| eu-a | 40% | 65% | 30% | Good |
| eu-b | 35% | 55% | 25% | Good |
| eu-c | 38% | 60% | 28% | Good |
| india-s | 25% | 45% | 40% | Excellent |
| india-w | 15% | 50% | 60% | Excellent |

### Growth Scenarios

**300 users (3x growth):**
- VM storage: ~95GB total (32GB per node) → Add 1 vmstorage (4 nodes)
- PostgreSQL: ~60GB → Still fits comfortably

**500 users (5x growth):**
- VM storage: ~160GB total (27GB per 6 nodes) → 6 vmstorage nodes
- PostgreSQL: ~100GB → Upgrade EU nodes to Netcup (256GB storage)

**1000 users (10x growth):**
- VM storage: ~315GB total → 8-10 vmstorage nodes
- PostgreSQL: ~200GB → Separate PostgreSQL cluster (dedicated nodes)
- Estimated cost: ~$100/mo

## Security Architecture

### Network Layers

```
Layer 1: Public Internet
├─ Port 22 (SSH) → Key-only auth, fail2ban
├─ Port 443 (HTTPS) → Application (Caddy/Nginx)
└─ All other ports: CLOSED

Layer 2: Tailscale VPN (100.64.1.0/24)
├─ PostgreSQL: 5432 (Tailscale only)
├─ etcd: 2379, 2380 (Tailscale only)
├─ VictoriaMetrics: 8400, 8480, 8481, 8482 (Tailscale only)
├─ Prometheus: 9090 (Tailscale only)
├─ Loki: 3100 (Tailscale only)
└─ Alertmanager: 9093 (Tailscale only)

Layer 3: localhost
├─ PostgreSQL connections via Unix socket (when local)
└─ Inter-process communication
```

### Secret Management

**Current approach (Phase 1):**
- NixOS secrets via `agenix` or `sops-nix`
- PostgreSQL passwords: Stored encrypted, decrypted at deploy
- Tailscale auth key: One-time use, ephemeral

**Future (when needed):**
- HashiCorp Vault for dynamic secrets
- Rotate credentials automatically

### Firewall Rules (iptables via NixOS)

```nix
networking.firewall = {
  enable = true;

  # Public ports
  allowedTCPPorts = [ 22 443 ];

  # Trust Tailscale interface completely
  trustedInterfaces = [ "tailscale0" ];

  # Default: DROP all other traffic
};
```

## Disaster Recovery

### Failure Scenarios

**Scenario 1: Single EU node fails (e.g., eu-a)**
- PostgreSQL: Automatic failover to eu-b (30 seconds)
- VictoriaMetrics: Continue with 2/3 vmstorage nodes
- etcd: Continue with 2/3 quorum
- **Impact:** Zero downtime

**Scenario 2: Two EU nodes fail (e.g., eu-a + eu-b)**
- PostgreSQL: Manual promotion of eu-c or india-s
- VictoriaMetrics: 1/3 vmstorage (degraded, data loss if replication factor=1)
- etcd: No quorum (can't elect leader)
- **Impact:** Downtime until manual intervention

**Scenario 3: All EU nodes fail (data center fire)**
- PostgreSQL: Promote india-s replica (async, may lose last 1-2 seconds)
- VictoriaMetrics: Historical data lost (query fails)
- etcd: Rebuild cluster on new nodes
- **Impact:** Partial outage, historical metrics unavailable

**Scenario 4: India nodes fail**
- PostgreSQL: No impact (EU cluster unaffected)
- VictoriaMetrics: Asian users query EU vmselect (slower but works)
- Monitoring: Prometheus/Loki down (rebuild from config)
- Backups: Restore to new node
- **Impact:** Degraded performance for Asian users

### Recovery Procedures

**RTO (Recovery Time Objective):**
- Single node: <30 seconds (automatic)
- Multiple nodes: <2 hours (manual)
- Complete data center: <4 hours (restore from backup)

**RPO (Recovery Point Objective):**
- PostgreSQL: <2 seconds (WAL archiving)
- VictoriaMetrics: <1 minute (last write batch)

## Monitoring Strategy

### Key Metrics

**Infrastructure:**
- Node availability (up/down)
- CPU usage (per core)
- Memory usage (RSS, cache)
- Disk usage (%, inodes)
- Network traffic (bytes/sec, errors)

**VictoriaMetrics:**
- Ingestion rate (samples/sec)
- Query latency (p50, p95, p99)
- Storage size per node
- vmstorage health
- vminsert queue depth

**PostgreSQL:**
- Replication lag (bytes, seconds)
- Transaction rate (commits/sec)
- Connection count
- Lock count
- Query duration (slow queries)

**etcd:**
- Cluster health
- Leader elections
- Proposal apply duration
- Disk sync duration

### Alerting Rules

**Critical (page on-call):**
- Node down >5 minutes
- PostgreSQL primary down
- etcd quorum lost
- Disk >90% full

**Warning (ticket for tomorrow):**
- CPU >80% for 30 minutes
- Memory >85% for 30 minutes
- Disk >80% full
- PostgreSQL replication lag >10 seconds

## Cost Analysis

### Current (Phase 1 - Hostkey Italy)

| Item | Quantity | Unit Cost | Monthly |
|------|----------|-----------|---------|
| Hostkey v2-mini | 3 | $5.23 | $15.69 |
| Oracle (free tier) | 2 | $0 | $0 |
| Tailscale | 1 | $0 | $0 |
| **Total** | | | **$15.69** |

### Future (Phase 4 - Netcup Austria)

| Item | Quantity | Unit Cost | Monthly |
|------|----------|-----------|---------|
| Netcup | 3 | $6.78 | $20.34 |
| Oracle (free tier) | 2 | $0 | $0 |
| Tailscale | 1 | $0 | $0 |
| **Total** | | | **$20.34** |

### Growth (500 users - 6 vmstorage)

| Item | Quantity | Unit Cost | Monthly |
|------|----------|-----------|---------|
| Netcup | 6 | $6.78 | $40.68 |
| Oracle (free tier) | 2 | $0 | $0 |
| **Total** | | | **$40.68** |

**ROI:**
- Current: $15.69/mo ÷ 10,000 monitors = $0.00157 per monitor
- At 500 users (50,000 monitors): $40.68/mo ÷ 50,000 = $0.00081 per monitor
- **50% cost reduction per monitor at scale** ✅

## Migration Strategy

### Zero-Downtime Migration Pattern

**Key insight:** Tailscale IPs don't change, physical nodes do.

```
Phase 1: Current State
  eu-a (Hostkey Italy): REMOVED_IP → 100.64.1.1

Phase 2: Add Netcup Parallel
  eu-a (Hostkey Italy): REMOVED_IP → 100.64.1.1
  netcup-temp: <new-ip> → 100.64.1.21

Phase 3: Swap Tailscale IPs
  eu-a (Hostkey Italy): REMOVED_IP → 100.64.1.99 (temp)
  netcup-1 (Austria): <new-ip> → 100.64.1.1

Phase 4: Rename
  eu-a (Netcup Austria): <new-ip> → 100.64.1.1
```

**Result:** All configs see same Tailscale IP (100.64.1.1), zero code changes.

## Open Issues

1. **Backup Encryption:** Should backups on india-w be encrypted at rest?
   - Current: No encryption (Oracle storage encrypted by default)
   - Future: Add GPG encryption if storing off-cloud

2. **Metrics Cardinality:** Should we limit label cardinality in VictoriaMetrics?
   - Risk: High cardinality (many unique label combinations) increases RAM usage
   - Mitigation: Monitor cardinality, add limits if needed

3. **PostgreSQL Minor Version:** Stay on latest minor (17.x) or pin specific version?
   - Current: Pin to 17.0 initially, upgrade manually
   - Future: Auto-update minors after testing in staging

4. **Certificate Management:** Use Let's Encrypt or self-signed for internal services?
   - Current: Tailscale HTTPS (automatic TLS)
   - Future: Let's Encrypt for public endpoints

## Success Metrics

**Performance:**
- [ ] Metric ingestion: 666 samples/sec sustained
- [ ] Query latency: <100ms p95 for dashboard queries
- [ ] PostgreSQL write: 222 inserts/sec sustained
- [ ] PostgreSQL failover: <30 seconds
- [ ] Backup completion: <15 minutes daily

**Reliability:**
- [ ] Uptime: 99.9% (43 minutes/month downtime budget)
- [ ] Zero data loss events
- [ ] Zero split-brain events
- [ ] Successful failover tested monthly

**Cost:**
- [ ] Monthly cost: <$30/mo Phase 1, <$50/mo Phase 4
- [ ] Cost per monitor: <$0.002/month
- [ ] Storage utilization: <80% (headroom for growth)
