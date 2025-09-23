# TimescaleDB vs Plain Postgres (Partitions + Materialized Views)
**Focus:** keeping **1 year** of uptime history for paid users (and 6 months for free) in an uptime monitoring app (Uptrack).

This doc explains *why* TimescaleDB is worth adopting for the `results` schema, and where plain Postgres + partitions + materialized views (MV) still make sense.

---

## TL;DR
- If you must retain **~1 year** of minute-level history for paid users, TimescaleDB’s **compression**, **continuous aggregates**, and **retention policies** reduce disk, keep dashboards fast, and remove a lot of custom maintenance code.
- Plain Postgres can do it with **daily partitions + MVs + cron/Oban refresh**, but at ~hundreds of millions to billions of rows, ops complexity and disk cost grow quickly.

---

## Workload & Scale Recap
- **Paid**: 100 users × 10 monitors @ 1-min ⇒ **1.44M rows/day** ⇒ **~525M rows/year** (retained).
- **Free** (example): 500 users × 100 monitors @ 4-min ⇒ **18M rows/day**, keep 6 months ⇒ **~3.2B rows/180 days** (if you keep full free history).
- Even if free is throttled, **paid alone** is already **hundreds of millions** of rows retained.

---

## What TimescaleDB Gives You

### 1) Native **Continuous Aggregates**
- Define rollups (1m, 5m, daily) and Timescale **auto-refreshes** just the new/changed time ranges.
- You specify a **policy** (start_offset/end_offset/interval). No custom Oban/cron workers needed.
- **Impact:** lower variance in dashboard latency, less app code, fewer operational sharp edges.

### 2) Built-in **Compression**
- Compress older chunks automatically (e.g., after 7 days).
- Typical **4–10×** reduction for time-series metrics (storage + IO).
- **Impact:** keep **1 year** of history affordably on smaller VMs; faster scans on cold data due to less IO.

### 3) Declarative **Retention Policies**
- Time-based TTL on hypertables and continuous aggregates.
- **Impact:** no custom partition create/drop scripts; one place to express data lifecycle (raw vs rollups).

### 4) **Adaptive Chunking** and Indexing
- Hypertables automatically split into chunks by time (and optionally space, e.g., `monitor_id`).
- Indexes and maintenance are scoped per-chunk.
- **Impact:** predictable query performance as data grows; simpler admin vs hand-rolled partitions.

### 5) **Time-Aware Functions**
- `time_bucket`, gap-filling, percentile, histogram helpers.
- **Impact:** simpler, faster queries for latency/uptime dashboards & SLA reports.

---

## What Plain Postgres Needs to Match It

### A) Partitioning + Indexing
- Create **daily partitions** for results, with indexes on `(monitor_id, ts DESC)` and `(account_id, ts DESC)`.
- **Maintenance jobs** to create tomorrow’s partition and drop old ones.

### B) Materialized Views (MVs)
- Build MVs for 1m/5m/daily rollups.
- **Refresh strategy**: `REFRESH MATERIALIZED VIEW CONCURRENTLY` on a schedule (e.g., every minute for 1m).
- Maintain **staleness tracking**, avoid lock contention, and ensure refresh performance as raw grows.

### C) Storage & IO
- Without compression, 500M+ rows/year can consume **60–120+ GB** (data + indexes), easily more depending on row width.
- **Impact:** bigger disks, more IO, longer backups; cold history scans slower.

### D) Operational Overhead
- Own the code/jobs for partition rotation, MV refresh cadence, failure handling, monitoring & alerting.
- **Impact:** more moving parts to babysit; potential backlogs if refresh jobs lag after incidents or maintenance windows.

---

## Performance & Cost Comparison (Qualitative)

| Aspect | TimescaleDB | Plain PG + MV |
|---|---|---|
| **Rollups freshness** | Continuous, incremental by policy | Manual `REFRESH CONCURRENTLY` jobs |
| **Storage** | Compressed chunks (4–10× smaller) | No native compression; bigger disks |
| **Retention** | Declarative policies per table/MV | Manual `DROP PARTITION` jobs |
| **Write throughput** | Optimized for time-series ingest | Good, but index/partition overhead grows |
| **Query speed (cold)** | Faster due to compression + chunk pruning | Slower scans on older data |
| **Ops complexity** | Lower (policies) | Higher (cron/Oban, scripts, monitoring) |
| **Feature lock-in** | Requires Timescale extension | Pure Postgres (portable) |

---

## When to Prefer TimescaleDB
- You **must** keep **1 year** of paid data (minute-level) and **6 months** for free.
- You want rollups **always fresh** without writing/maintaining refresh jobs.
- You need to control **storage growth** without buying large disks.
- Your dashboards should remain **fast** even for long look-backs.

## When Plain Postgres May Suffice
- History window is **short** (≤30–60 days total).  
- Smaller user base (≤200 users total) and low analytics pressure.
- You prefer **no extensions** and can afford to build/operate refresh/retention jobs.

---

## Recommended Layout (Timescale in `results` only)
- Keep **3 schemas** in one DB initially: `app` (vanilla PG), `oban` (vanilla PG), `results` (Timescale).
- **Two hypertables** for different retention windows:  
  - `results.monitor_results_paid` → **365d** retention, compress after 7d.  
  - `results.monitor_results_free` → **180d** retention, compress after 7d.
- Expose a `results.monitor_results` **view** (UNION ALL) for unified reads.
- Continuous aggregates: 1m (3–14d), 5m (90–180d), daily (1–2y).

---

## Migration & Future-Proofing
- Because you use a separate **ResultsRepo**, you can later:
  - Move Timescale to its **own VM/cluster** by flipping `RESULTS_DATABASE_URL`.
  - Or migrate to **ClickHouse** if you outgrow Timescale’s single-node limits (dual-write + backfill).

---

## Edge Cases & Pitfalls
- **Managed PG limitations:** some providers don’t support Timescale. On Hetzner VMs you control Postgres and can enable it.
- **Citus + Timescale** in the same cluster is **not recommended**. If you adopt Citus for app data, keep Timescale isolated to `results` or a different cluster.
- **Compression quirks:** compressed chunks are slower to update; ensure **write path only touches recent (uncompressed) data**.
- **Statement timeouts:** set shorter timeouts for dashboard roles to protect OLTP.

---

## Conclusion
For **1-year historical uptime logs** at minute granularity, TimescaleDB materially reduces **storage**, **ops work**, and **latency variance**. You *can* do it on plain Postgres with partitions + MVs, but the ongoing cost in disk and engineering time will exceed the simplicity Timescale gives you—especially once you cross **hundreds of millions** of retained rows.
