# Database Strategy for Uptime Monitoring

## Goals
- Sustain large probe volumes at low cost.
- Keep dashboards and alerts responsive.
- Control storage growth via retention and aggregation.

## Two Write Models
- Store Every Probe
  - Pros: full fidelity for debugging and analytics.
  - Cons: 1,000,000 monitors @ 1/min ⇒ ~16,667 inserts/s; requires time-series DB or heavily partitioned Postgres on fast NVMe.
- Store State-Changes + Aggregates (Recommended)
  - Persist only transitions (up↔down) and periodic rollups (1–5 min).
  - Typical steady-state insert rate: <100–500 inserts/s cluster-wide since most probes are “up”.
  - Keeps costs low and queries fast for SLOs/uptime.

## Postgres Path (Cost-Efficient & Simple)
- Schema (raw minimal):
  - `monitor_checks(id bigint, monitor_id bigint, status char(2) or enum, status_code smallint, response_time integer, checked_at timestamptz, error_message text)`
  - Avoid storing bodies; if needed, store short snippets.
- Indexes:
  - `(monitor_id, checked_at DESC)` covering most lookups.
  - Partial on downs: `(monitor_id, checked_at) WHERE status = 'down'`.
- Partitioning (native):
  - Range by day (or hour at very high rates) on `checked_at`.
  - Use `ALTER TABLE ... ATTACH PARTITION` per day; drop old partitions for retention.
- Retention & Aggregates:
  - Raw retention: 7–14 days.
  - Aggregates table: `monitor_minute(id, monitor_id, ts, uptime_pct, avg_latency_ms, down_count)`.
  - Maintain via scheduled job; keep 90–180 days.
- Tuning tips:
  - NVMe SSDs, `synchronous_commit = off` for batch loads, `wal_compression = on`.
  - Careful `autovacuum` thresholds per partition; avoid bloating.
  - Use `UNLOGGED` tables for transient staging/batches if needed.
  - Pgbouncer in transaction mode for many short-lived connections.

## TimescaleDB Path (If You Need More Raw Data)
- Hypertables on `monitor_checks(time, monitor_id)` with compression.
- Built-in continuous aggregates for minute/hour rollups.
- Pros: simpler time-series management, retention, compression.
- Cons: added dependency and ops; some features are license-restricted in newer versions.

## ClickHouse Path (High-Throughput Analytics)
- Columnar, excellent compression and ingest; great for analytics queries and long retention.
- Use MergeTree with partition by day and order by `(monitor_id, checked_at)`.
- Pros: cheap storage, very fast scans.
- Cons: eventual consistency patterns, different SQL, joins less friendly; pair with Postgres for relational data.

## VictoriaMetrics (Metrics-Oriented)
- Very simple ops, great write throughput and retention; ideal if you store just status/latency as time series.
- Cons: limited ad-hoc relational queries; pair with Postgres for metadata.

## Write Path Recommendations
- Prefer HEAD for simple uptime; small GET if keyword/content checks needed.
- Truncate/omit response bodies; store error snippets only.
- Jitter schedules uniformly across the minute; avoid bursts.
- Apply bounded concurrency and short timeouts.
- Batch writes when feasible:
  - Collect results in ETS/buffer and insert in small batches (50–500 rows) to reduce commit overhead.

## Query Patterns
- Latest state per monitor: use `(monitor_id, checked_at DESC)` index or upsert a cached `monitor_state` table.
- Uptime over window: compute from aggregates; avoid scanning raw.
- Incident timelines: join state-change rows within time ranges; ensure partitions keep scans bounded.

## Sizing Guidance (State-Change + Aggregates)
- Single strong Postgres node (managed or self-hosted): 8 vCPU, 32 GB RAM, NVMe; scale to 16/64 as needed.
- Expected steady inserts: <500/s cluster-wide; p95 reads are light.
- Horizontal worker shards (Elixir/Go) fan-in writes to Postgres; keep pool sizes conservative (e.g., 20–50 connections).

## Sizing Guidance (Store Every Probe)
- Time-series cluster (e.g., ClickHouse or VictoriaMetrics) with 3 nodes, 16–32 vCPU, 64–128 GB RAM, NVMe.
- Optional Kafka for backpressure and batching, but not strictly required if workers batch directly.
- Keep Postgres for metadata, incidents, auth, and UI.

## Cost Levers
- Store less: state-changes + minute aggregates.
- Tight retention: drop old partitions routinely.
- Skinny rows: avoid large text; short error messages.
- Regional workers to reduce RTT and egress.

## Summary
- For best price/performance, use Postgres with state-change + aggregates and strict retention.
- Adopt a time-series DB only if you truly need every raw probe or long retention at scale.
- Your main constraints are DB write rate and network egress; optimize those before changing runtimes.

