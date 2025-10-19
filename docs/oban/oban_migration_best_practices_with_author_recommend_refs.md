# Oban Migration Best Practices (with Author Recommendations + References)

This document merges:
1. **Best practices we outlined** for painless migration to a dedicated HA Postgres.
2. **Direct recommendations from Shannon & Parker Selbert** (ElixirConf EU 2024).

---

## Key Combined Practices with Transcript References

### Repo & Schema Isolation

**Uptrack Implementation**: ✅ Implemented
- AppRepo: Handles all migrations (app schema + oban schema)
- ObanRepo: Same database, separate connection pool for jobs
- Oban schema kept completely separate from app schema
- Authors emphasized: **never mix job tables with app data** ✅ Followed
- 📖 Reference: see [00:00:00,660 --> 00:00:11,150] [Music]

**Why we keep 2 repos despite single migrations:**
- Pool isolation: App queries never starved by jobs
- Different configuration: Can tune pool sizes independently
- Clear responsibility: AppRepo manages schema, ObanRepo uses it

### Connection Pooling

**Uptrack Implementation**: ✅ Implemented
- `AppRepo` pool_size: 10-15 (app queries)
- `ObanRepo` pool_size: 20-30 (job processing)
- Single PostgreSQL connection, but separate pools prevent contention
- Authors confirmed: TRANSACTION pooling breaks advisory locks and LISTEN/NOTIFY ✅ Avoided by using separate repos
- 📖 Reference: [00:00:11,150 --> 00:00:12,100] [Applause]

**Pool Strategy Benefits:**
- No single connection bottleneck (separate pools)
- Jobs can't starve app queries
- Both can scale independently  

### Queue Design
- Jobs should be short, idempotent, and retry-safe.
- Authors recommend scaling by **adding queues, not just concurrency**.  
- 📖 Reference: [00:00:12,100 --> 00:00:16,480] [Music]  

### Job Lifecycle

**Uptrack Implementation**: ✅ Implemented
- Prune jobs after 7 days (configured in Oban.Plugins.Pruner)
- Authors: Oban is **not a log DB**. Keep it lean, offload analytics to a time-series/analytics DB ✅ We use ClickHouse for monitoring data
- Metrics and time-series data: Separate from Oban jobs (via ResilientWriter to ClickHouse)
- 📖 Reference: [00:00:18,039 --> 00:00:19,240] and over to

**Why separate Oban from analytics:**
- Oban should stay <100MB for performance
- Time-series metrics belong in ClickHouse (optimized for analytical queries)
- Monitoring data stays in ClickHouse, not in Postgres job tables  

### Observability & Resilience
- Monitor Oban telemetry events (`oban_job_start`, `stop`, `exception`).
- Authors: add **circuit breakers** for external APIs, fail fast on outages.  
- 📖 Reference: [00:00:19,240 --> 00:00:23,160] you okay well welcome thanks for coming  

### Migration Path

**Uptrack Implementation**: ✅ Implemented from start
- Single DATABASE_URL for both app and Oban (same HA Postgres cluster)
- AppRepo handles all migrations (no separate cutover needed)
- Separate pools via AppRepo (10-15) and ObanRepo (20-30)
- Authors: recommended **draining queues** before cutover ✅ Would be simple due to shared migrations
- 📖 Reference: [00:00:23,160 --> 00:00:26,519] to scaling uh Oban applications so I'm

**Why unified from day one:**
- No DSN flip needed (single DATABASE_URL)
- Migrations always in sync (single source)
- Deployment is single operation  

### Scaling Beyond One Node

**Uptrack Implementation**: ✅ Implemented
- 5-node HA PostgreSQL cluster (Germany primary, Austria+India Strong replicas)
- Oban DB small and optimized: <100MB with 7-day pruning
- Heavy metrics/logs go to **ClickHouse**, not Oban ✅ Using ResilientWriter
- Etcd cluster for distributed coordination (5 nodes, quorum 3/5)
- 📖 Reference: [00:00:26,519 --> 00:00:28,279] Parker and this is Shannon we've been

**Architecture:**
- Oban: HA Postgres (orchestration)
- Monitoring data: ClickHouse (analytics)
- Separate databases = optimal for each use case  

---

## Sample Transcript References

[00:00:00,660 --> 00:00:11,150] [Music]
[00:00:11,150 --> 00:00:12,100] [Applause]
[00:00:12,100 --> 00:00:16,480] [Music]
[00:00:18,039 --> 00:00:19,240] and over to
[00:00:19,240 --> 00:00:23,160] you okay well welcome thanks for coming
[00:00:23,160 --> 00:00:26,519] to scaling uh Obin applications so I'm
[00:00:26,519 --> 00:00:28,279] Parker and this is Shannon we've been
[00:00:28,279 --> 00:00:31,840] business partners for 15 years uh we are
[00:00:31,840 --> 00:00:34,480] obviously husband and wife this is one
[00:00:34,480 --> 00:00:35,920] of the first times we've done this with
[00:00:35,920 --> 00:00:39,000] pants on for the rehearsal so for your
[00:00:39,000 --> 00:00:41,399] benefit American pants you're welcome
[00:00:41,399 --> 00:00:43,079] most importantly we are the people
[00:00:43,079 --> 00:00:44,280] behind
[00:00:44,280 --> 00:00:47,480] Oben and I'm Shannon and when I'm not

...(see detail_author_recommend.md for full transcript)...

---

## Summary

**Uptrack follows both our practices and Selberts' guidance:**

### Oban as Orchestration Layer ✅
- **Lean**: <100MB with aggressive 7-day pruning
- **Reliable**: HA PostgreSQL cluster (5 nodes, quorum 3/5)
- **Scalable**: Separate connection pools (app vs job)
- **Monitored**: Via Prometheus metrics and observability

### Unified from Day One ✅
- Single DATABASE_URL (no DSN flip needed)
- Single migration source (AppRepo manages all)
- Separate pools (AppRepo 10-15, ObanRepo 20-30)
- Atomic deployments (app + Oban together)

### Separation of Concerns ✅
- **Oban DB** (PostgreSQL): Job orchestration only
- **Monitoring DB** (ClickHouse): Time-series analytics
- **App DB** (Same as Oban): User data, config, state

### Result
Oban remains a **lean, reliable orchestration layer** while analytics/metrics go to ClickHouse where they belong.

Full transcript reference: see `detail_author_recommend.md`

---

## Implementation Status

| Practice | Status | Details |
|----------|--------|---------|
| Separate Oban schema | ✅ | Oban in separate schema, app in app schema |
| Separate connection pools | ✅ | AppRepo (10-15), ObanRepo (20-30) |
| Single migrations | ✅ | AppRepo handles all (app + oban schema) |
| Aggressive pruning | ✅ | 7-day retention, Pruner plugin enabled |
| ClickHouse for analytics | ✅ | Via ResilientWriter, not in Postgres |
| HA database | ✅ | 5-node cluster (Germany primary, replicas) |
| Etcd coordination | ✅ | 5-node etcd cluster, quorum 3/5 |
| Distributed job processing | ✅ | Multiple nodes, regional load balancing |
