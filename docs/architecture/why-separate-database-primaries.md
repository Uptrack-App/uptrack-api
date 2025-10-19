# Why Separate Database Primaries Across Nodes

**TL;DR:** Never put both PostgreSQL PRIMARY and ClickHouse PRIMARY on the same node. Always separate them across different nodes to minimize blast radius, reduce failover complexity, and maintain observability during incidents.

---

## Table of Contents

1. [The Core Question](#the-core-question)
2. [Architecture Comparison](#architecture-comparison)
3. [10 Critical Reasons to Separate Primaries](#10-critical-reasons-to-separate-primaries)
4. [Real-World Failure Scenarios](#real-world-failure-scenarios)
5. [The Replica Paradox](#the-replica-paradox)
6. [The Golden Rules](#the-golden-rules)
7. [Decision Matrix](#decision-matrix)

---

## The Core Question

**Question:** "We have replicas for both databases. Why does it matter if both primaries are on the same node?"

**Answer:** Replicas prevent **DATA LOSS**. Primary separation prevents **COMPLICATED FAILURES** and **EXTENDED DOWNTIME**.

---

## Architecture Comparison

### ❌ Co-located (Both Primaries on Same Node)

```
Node A (Oracle Mumbai):
├─ PostgreSQL PRIMARY ← Both primaries here
├─ ClickHouse PRIMARY ← High risk!
└─ Phoenix app

Node B (Netcup Germany):
├─ PostgreSQL REPLICA
├─ ClickHouse REPLICA
└─ Phoenix app

Node C (OVH Virginia):
├─ ClickHouse REPLICA
└─ Phoenix app
```

**Single Point of Failure:** If Oracle dies, BOTH primaries die simultaneously.

---

### ✅ Separated (Primaries on Different Nodes)

```
Node A (Oracle Mumbai):
├─ PostgreSQL PRIMARY ← Only Postgres here
└─ Phoenix app

Node B (Netcup Germany):
├─ ClickHouse PRIMARY ← ClickHouse on different node
├─ PostgreSQL REPLICA
└─ Phoenix app

Node C (OVH Virginia):
├─ ClickHouse REPLICA
└─ Phoenix app
```

**Isolated Failures:** Each primary can fail independently without affecting the other.

---

## 10 Critical Reasons to Separate Primaries

### 1. 🔥 Single Point of Failure (CRITICAL)

**Co-located:**
- ❌ One node failure = BOTH primary databases offline
- ❌ Complete write capability lost
- ❌ Must fail over TWO systems simultaneously
- ❌ Higher complexity = higher failure risk

**Separated:**
- ✅ One node failure = ONE primary database offline
- ✅ Other primary keeps running
- ✅ Only ONE system needs failover
- ✅ Partial availability maintained

**Example:**

**Co-located - Oracle crashes:**
```
03:00:00 - Oracle dies
03:00:00 - Postgres writes: STOPPED ❌
03:00:00 - ClickHouse writes: STOPPED ❌
03:00:00 - Monitoring data: LOST ❌
03:00:30 - Postgres auto-fails to Netcup ✅
03:05:00 - ClickHouse manually promoted ✅
Total outage: 5 minutes for EVERYTHING
```

**Separated - Oracle crashes:**
```
03:00:00 - Oracle dies
03:00:00 - Postgres writes: STOPPED ❌
03:00:00 - ClickHouse writes: CONTINUE ✅ (on Netcup!)
03:00:00 - Monitoring data: STILL BEING COLLECTED ✅
03:00:30 - Postgres auto-fails to Netcup ✅
Total outage: 30 seconds for Postgres, 0s for ClickHouse
```

---

### 2. 💾 Resource Contention

**Co-located on Oracle (24GB RAM):**
```
PostgreSQL:   12-14 GB
ClickHouse:    8-10 GB
Phoenix:       2-3 GB
─────────────────────
Total:        22-27 GB ← OVER LIMIT!
```
- ❌ Out of memory risk during spikes
- ❌ Databases compete for same RAM
- ❌ Postgres cache evicted by ClickHouse
- ❌ Shared I/O bandwidth (WAL + merges fight)

**Separated:**

**Oracle (24GB):**
```
PostgreSQL:   16-18 GB ← Can use MORE!
Phoenix:       2-3 GB
─────────────────────
Total:        18-21 GB
Free:          3-6 GB ← Healthy headroom
```

**Netcup (12GB):**
```
ClickHouse:    5-6 GB (dedicated)
Postgres Rep:  3 GB
Phoenix:       2 GB
─────────────────────
Total:        10-11 GB
Free:          1-2 GB
```

---

### 3. ⚡ Write Load Distribution

During monitoring bursts (1000 monitors × 3 regions = 3000 writes/min):

**Co-located:**
```
Oracle Node:
├─ Postgres: 3000 status updates/min
├─ ClickHouse: 3000 metric inserts/min
└─ Total: 6000 writes/min on ONE disk
   → I/O bottleneck
   → Write latency spikes
```

**Separated:**
```
Oracle:
└─ Postgres: 3000 writes/min (200GB NVMe handles easily)

Netcup:
└─ ClickHouse: 3000 writes/min (252GB NVMe handles easily)

Total I/O capacity = 2x better
```

---

### 4. 🔄 Failover Complexity

**Co-located - Oracle fails:**
```
Step 1: Both Postgres AND ClickHouse primaries die
Step 2: Patroni auto-fails Postgres (30s) ✅
Step 3: ClickHouse failover needed (manual?)
Step 4: Data in ClickHouse write buffer at risk
Step 5: Promote ClickHouse replica (complexity)
Step 6: Verify which replica has latest data

RTO: 30s (Postgres) + minutes to hours (ClickHouse)
Complexity: HIGH (coordinated recovery)
Data loss risk: Possible
```

**Separated - Oracle fails:**
```
Step 1: Only Postgres primary dies
Step 2: Patroni auto-fails Postgres to Netcup (30s) ✅
Step 3: ClickHouse unaffected (already on Netcup)
Step 4: Done

RTO: 30s
Complexity: LOW (single system)
Data loss risk: None
```

---

### 5. 🎯 Blast Radius

**Co-located:**
```
1 node failure = 2 database primaries lost
Blast radius: 100% of write capacity
```

**Separated:**
```
1 node failure = 1 database primary lost
Blast radius: 50% of write capacity
```

---

### 6. 🔥 The Critical Issue for Monitoring SaaS: Observability During Outage

**This is THE killer argument for a monitoring product:**

**Co-located - Oracle fails:**
```
03:00 - Postgres DOWN ❌
03:00 - ClickHouse DOWN ❌
03:00 - Monitor checks can't write results
03:00 - YOU ARE BLIND to what's happening
03:01 - Can't query ClickHouse to see incident timeline
03:01 - Can't see which monitors are affected
03:30 - Postgres up, ClickHouse still down
03:30 - Still can't see monitoring data
```

**You're trying to fix an outage while BLIND.**

**Separated - Oracle fails:**
```
03:00 - Postgres DOWN ❌
03:00 - ClickHouse STILL UP ✅ (on Netcup!)
03:00 - Monitor checks KEEP WRITING to ClickHouse
03:00 - You can SEE in real-time:
        ✓ "3000 monitors still being checked"
        ✓ "Only Postgres writes timing out"
        ✓ "ClickHouse shows Oracle region monitors healthy"
        ✓ Dashboard still renders
03:01 - You know exact scope: "Postgres issue, monitoring fine"
03:30 - Postgres up, ClickHouse never went down
```

**For a monitoring product: Maintaining observability during incidents is CRITICAL.**

---

### 7. 🧠 Cascading Failures

**Co-located: Network saturation during failover**
```
Oracle fails → Need to sync BOTH databases to Netcup
├─ Postgres WAL: 500MB syncing to Netcup
├─ ClickHouse blocks: 300MB syncing to Netcup
├─ Both competing for Netcup's network bandwidth
├─ Slower failover for BOTH
└─ Total RTO: 95 seconds (vs expected 15s)
```

**Separated: Network saturation avoided**
```
Oracle fails → Only Postgres needs sync
├─ Postgres WAL: 500MB syncing to Netcup
├─ Full bandwidth available (no competition)
├─ ClickHouse: Already on Netcup (zero impact)
└─ Total RTO: 15 seconds (as expected)
```

---

### 8. ⏱️ Recovery Time Objective (RTO)

**Co-located:**
```
Postgres failover: 30s (automated)
ClickHouse failover: 30s-2hr (depends on automation)
Complete service RTO: MAX(30s, 30s-2hr) = 30s-2hr

For 99.95% uptime SLA:
- 30s outage = 0.001% downtime ✅
- 30min outage = 0.058% downtime ❌ BLOWS SLA
```

**Separated:**
```
Oracle fails:
├─ Postgres: 30s failover
├─ ClickHouse: 0s (already on Netcup)
└─ Complete RTO: 30s ✅

Netcup fails:
├─ Postgres: 0s (already on Oracle)
├─ ClickHouse: Manual failover (non-urgent, data spools)
└─ Complete RTO: 0s for critical functions ✅
```

---

### 9. 🎲 Failure Probability

**Co-located:**
```
P(successful recovery) = P(Postgres OK) × P(ClickHouse OK)
                       = 0.999 × 0.999
                       = 0.998
                       = 99.8%

Failure rate: 0.2% (1 in 500 failovers has issues)
```

**Separated:**
```
P(successful recovery) = P(affected DB works)
                       = 0.999
                       = 99.9%

Failure rate: 0.1% (1 in 1000 failovers has issues)

Separation HALVES your failover risk.
```

---

### 10. 💥 Resource Exhaustion Example

**Co-located: Memory leak scenario**
```
Hour 1: ClickHouse has memory leak
Hour 2: ClickHouse using 18GB (should be 8GB)
Hour 3: Postgres squeezed to 4GB (should be 14GB)
Hour 4: Postgres starts swapping → Slow queries
Hour 5: Postgres timeouts → OOM killer triggered
Hour 6: OOM kills BOTH Postgres AND ClickHouse
Hour 6: Both primaries dead, both fail over

Impact: Complex incident, coordinated failover needed
```

**Separated: Memory leak scenario**
```
Hour 1: ClickHouse leak on Netcup
Hour 2: ClickHouse using 10GB (bad, but isolated)
Hour 3: OOM kills ClickHouse on Netcup
Hour 3: Auto-promote OVH ClickHouse replica

Postgres on Oracle: Totally unaffected, 18GB RAM available

Impact: Only ClickHouse affected, simple diagnosis
```

---

## Real-World Failure Scenarios

### Detailed Timeline: Oracle Node Dies at 3am

#### Co-located Design

```
03:00:00 - Oracle loses power
03:00:01 - ALL connections drop (Postgres + ClickHouse)
03:00:01 - Oban workers run checks → Results can't be written ❌
03:00:05 - ClickHouse writes FAIL ❌
03:00:10 - PagerDuty: 3 alerts (Postgres, ClickHouse, Oracle)
03:00:10 - More checks run → 3000 results LOST ❌
03:00:15 - Patroni promotes Postgres to Netcup ✅
03:00:16 - Postgres writes resume ✅
03:00:20 - ClickHouse STILL BROKEN ❌
03:00:30 - Another 3000 check results lost ❌
03:01:00 - You wake up, check dashboard: BROKEN ❌
03:02:00 - SSH to check logs
03:03:00 - Check ClickHouse replication lag
03:04:00 - Run manual promotion script
03:04:10 - Update Phoenix configs
03:04:40 - System fully recovered ✅
03:05:00 - Check data loss: 14,000 points LOST ❌

Total RTO: 4min 40s
Data loss: 14,000 monitoring data points
User impact: 4+ min partial outage
On-call: 15min incident response
```

#### Separated Design

```
03:00:00 - Oracle loses power
03:00:01 - Only Postgres connections drop
03:00:01 - Oban workers run checks → Write to ClickHouse ✅
03:00:02 - ClickHouse on Netcup: Business as usual ✅
03:00:03 - Patroni detects Postgres leader missing
03:00:05 - Phoenix spools Postgres writes (queued)
03:00:08 - Patroni prepares promotion
03:00:10 - PagerDuty: 2 alerts (Postgres, Oracle)
03:00:10 - More checks run → All data captured ✅
03:00:15 - Patroni promotes Postgres to Netcup ✅
03:00:16 - Queued writes flush ✅
03:00:20 - All systems operational ✅
03:00:30 - Checks running normally ✅
03:01:00 - You check phone: Dashboard WORKING ✅
03:02:00 - See: "Patroni auto-recovered"
03:02:30 - Acknowledge alert, back to sleep 😴

Total RTO: 16 seconds
Data loss: ZERO
User impact: 16s "can't create monitors"
On-call: 2min to verify, back to sleep
```

---

## The Replica Paradox

**Question:** "We have replicas in both designs, why are they different?"

**Answer:** The difference isn't "do we have replicas?" The differences are:

### 1. How many replicas activate at once?
- **Co-located:** 2 simultaneous failovers
- **Separated:** 1 failover at a time

### 2. Do both primaries fail together?
- **Co-located:** Yes (single node)
- **Separated:** No (different nodes)

### 3. Is there always ONE primary running?
- **Co-located:** No (both down during failover)
- **Separated:** Yes (one primary always alive)

### Airplane Engine Analogy

**Co-located: Both engines on same wing**
```
Left Wing: Engine 1 + Engine 2
Right Wing: Backup 1 + Backup 2

Wing damaged → BOTH engines fail → Start TWO backups
High complexity, high risk
```

**Separated: One engine per wing**
```
Left Wing: Engine 1 (backup on right)
Right Wing: Engine 2 (backup on left)

Wing damaged → ONE engine fails → Other keeps running
Plane stays aloft while backup starts
```

---

## The Golden Rules

### Rule 1: Separate Database Primaries

**Never put multiple database primaries on the same node.**

- ✅ PostgreSQL PRIMARY on Node A
- ✅ ClickHouse PRIMARY on Node B
- ❌ Both primaries on Node A

### Rule 2: Use Odd Numbers for Consensus Clusters

**ALWAYS use odd numbers (3, 5, 7) for distributed consensus systems like etcd.**

#### Why Even Numbers Are Bad

For consensus-based HA (etcd, Patroni, distributed systems):

| Nodes | Quorum | Failures Tolerated | HA Value | Recommendation |
|-------|--------|-------------------|----------|----------------|
| 1 | 1 | 0 | ❌ Terrible | Never |
| 2 | 2 | 0 | ❌ Useless | Never |
| **3** | **2** | **1** | ✅ **Good** | **Most common** |
| 4 | 3 | 1 | ⚠️ Worse than 3 | Don't use |
| **5** | **3** | **2** | ✅ **Better** | Enterprise |
| 6 | 4 | 2 | ⚠️ Worse than 5 | Don't use |
| **7** | **4** | **3** | ✅ **Best** | Large scale |

**Pattern: ODD numbers good, EVEN numbers bad**

#### The Math

**3-node cluster:**
```
Total nodes: 3
Quorum needed: 2 (majority)
Can tolerate: 1 failure

Scenarios:
├─ 3 alive: ✅ Quorum (3/3)
├─ 2 alive: ✅ Quorum (2/3) ← Minimum
└─ 1 alive: ❌ No quorum (1/3)
```

**4-node cluster:**
```
Total nodes: 4
Quorum needed: 3 (majority)
Can tolerate: 1 failure (SAME AS 3!)

Scenarios:
├─ 4 alive: ✅ Quorum (4/4)
├─ 3 alive: ✅ Quorum (3/4) ← Minimum
├─ 2 alive: ❌ No quorum (2/4) ← 50/50 split!
└─ 1 alive: ❌ No quorum (1/4)
```

**Critical difference:**
```
3 nodes: Need 66% to fail before losing quorum
4 nodes: Need 50% to fail before losing quorum

4 nodes has LOWER failure threshold!
```

#### Cost-Benefit Analysis

| Setup | Cost/mo | Failures Tolerated | Uptime | Verdict |
|-------|---------|-------------------|--------|---------|
| **3 nodes** | **€10-11** | **1** | **99.99%** | **✅ Best value** |
| 4 nodes | €15-19 | 1 | 99.99% | ❌ Waste of money |
| 5 nodes | €20-27 | 2 | 99.999% | 🤔 Enterprise only |

#### Network Partition Risk

**3-node cluster:**
```
Never has 50/50 split
Always clear majority side
Split-brain prevention: Automatic
```

**4-node cluster:**
```
Can have 2-2 split
Neither side has majority
Both sides shut down → TOTAL OUTAGE
Split-brain prevention: Causes outage
```

---

## Decision Matrix

### When to Co-locate (DON'T)

❌ Never recommended for production systems

### When to Separate (DO)

✅ **Always** for production HA systems

### Migration Path

If you currently have co-located primaries:

**Step 1:** Move ClickHouse PRIMARY to Node B
```bash
# On Node B (Netcup)
clickhouse-client -q "ALTER TABLE ... MODIFY SETTING ..."
# Promote to primary

# Update Phoenix configs
CLICKHOUSE_HOST=netcup_tailscale_ip
```

**Step 2:** Keep PostgreSQL PRIMARY on Node A
```bash
# No changes needed
# Patroni already manages this
```

**Step 3:** Verify separation
```bash
# Check Postgres primary
patronictl list

# Check ClickHouse primary
clickhouse-client -q "SELECT * FROM system.replicas"
```

**Step 4:** Test failover
```bash
# Simulate Node A failure
systemctl stop patroni

# Verify only Postgres fails over
# ClickHouse should be unaffected
```

---

## Summary Scorecard

| Factor | Co-located | Separated | Winner |
|--------|------------|-----------|--------|
| Single Point of Failure | ❌ CRITICAL RISK | ✅ Isolated | **SEPARATED** |
| Resource Contention | ❌ Tight/OOM risk | ✅ Comfortable | **SEPARATED** |
| Write Distribution | ❌ Bottleneck | ✅ Distributed | **SEPARATED** |
| Failover Complexity | ❌ Complex | ✅ Simple | **SEPARATED** |
| Blast Radius | ❌ 100% | ✅ 50% | **SEPARATED** |
| User Impact | ❌ Total outage | ✅ Partial | **SEPARATED** |
| Observability | ❌ Blind during outage | ✅ Maintained | **SEPARATED** |
| Maintenance | ❌ Risky | ✅ Easy | **SEPARATED** |
| Cost | = Same | = Same | **TIE** |
| Ops Complexity | ✅ Simpler | ❌ Complex | **CO-LOCATED** |
| Performance | ❌ Contention | ✅ Isolated | **SEPARATED** |

**Score: SEPARATED wins 9-1 with 1 tie**

---

## Final Recommendation

### For Uptrack (and any HA monitoring SaaS):

**✅ Use Separated Architecture:**

```
Node A (Oracle Mumbai - FREE):
├─ PostgreSQL PRIMARY
├─ Phoenix + Oban
└─ 24GB RAM: Plenty for Postgres alone

Node B (Netcup Germany - €5.26/mo):
├─ ClickHouse PRIMARY
├─ PostgreSQL REPLICA
├─ Phoenix + Oban
└─ 12GB RAM: Enough for both

Node C (OVH Virginia - €5.26/mo):
├─ ClickHouse REPLICA
├─ Phoenix + Oban
└─ 8GB RAM: Sufficient

Total: €10.52/month
HA: 99.99% uptime
Fault tolerance: 1 node failure
Consensus nodes: 3 (odd number ✅)
```

**The minor operational complexity of remembering "which primary is where" is NOTHING compared to:**
- ✅ 50% less blast radius per failure
- ✅ Better resource utilization
- ✅ Simpler failover
- ✅ Maintained observability during incidents
- ✅ Graceful degradation
- ✅ Easier maintenance
- ✅ Lower failure probability
- ✅ Odd-number consensus cluster

---

## References

- [PostgreSQL HA with Patroni](https://patroni.readthedocs.io/)
- [ClickHouse Replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication)
- [etcd Consensus](https://etcd.io/docs/v3.5/learning/why/)
- [Distributed Systems Theory](https://www.the-paper-trail.org/post/2014-08-09-distributed-systems-theory-for-the-distributed-systems-engineer/)

---

**Last Updated:** 2025-10-10
**Document Version:** 1.0
**Status:** Production Recommendation
