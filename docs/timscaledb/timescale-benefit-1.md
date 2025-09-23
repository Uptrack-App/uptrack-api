Good question — let’s be very practical. You already have Postgres with daily partitions. Why bother with TimescaleDB for the results schema?

🚀 Benefits of TimescaleDB for results
1. Continuous aggregates (auto rollups)

In plain Postgres: you create materialized views and refresh them yourself with Oban jobs or cron. That’s extra load + code to maintain.

With Timescale: you declare a continuous aggregate and Timescale automatically refreshes it in the background according to a policy.

Example: 1-minute uptime/latency rollup for the past 3 days, refreshed every minute.

Benefit: dashboards can always query pre-rolled data (fast), no manual refresh workers needed.

2. Native compression (big win at your scale)

Raw results are huge: at 1,000 users you’ll generate ~25M rows/day.

Timescale can compress old chunks (e.g. older than 7 days) to 10–20% of original size.

Raw 90 days ≈ 2.25B rows → terabytes uncompressed, maybe a few hundred GB compressed.

Benefit: keep longer history on smaller disks, cheaper Hetzner boxes.

3. Retention policies (automatic TTL)

In plain Postgres: you must drop old partitions yourself with a job.

In Timescale: add_retention_policy automatically drops/compresses old data.

Example: keep raw for 30d, compress for 90d, drop beyond.

Benefit: no custom partition-rotation code, fewer moving parts.

4. Adaptive chunking & indexes

Timescale splits data into chunks (like partitions) automatically.

It also manages indexes per chunk so queries on time ranges don’t scan everything.

Benefit: you don’t need to hand-roll partition scripts or indexes — just set a chunk_time_interval.

5. Time-bucket functions

Timescale has handy functions like time_bucket() and fast percentile, histogram, gap-filling, and moving average helpers.

Benefit: easier to implement latency histograms, uptime % over sliding windows, etc., with less query complexity.

6. Scaling to high insert rates

Postgres partitions can handle high inserts, but managing billions of rows gets tricky.

Timescale is tuned for sustained insert throughput (100k+/sec) by optimizing WAL writes, chunking, and indexes.

Benefit: smoother growth curve, less manual DBA work.

⚖️ Trade-offs

More overhead on a small $50 Hetzner box: the extension uses extra CPU/RAM. At tiny scale (<200 users) you might be fine with just Postgres partitions.

Migration complexity: once you use Timescale features (continuous aggs, compression), you can’t run without the extension. If you later want to move results to ClickHouse, you’ll need a backfill step.

Compatibility: can’t run Timescale + Citus in the same cluster (they both hook deep into planner). If you want Citus for app data, you’ll need a separate DB cluster anyway.

✅ When Timescale helps in Uptrack

When raw results hit hundreds of millions of rows and you want to keep more than 30 days history.

When you want auto rollups (1m, 5m, daily) without building custom refresh jobs.

When you want cheap long-term retention with compression.

When you want Postgres familiarity (SQL, Ecto, Oban) but “time-series smarts” for free.

📝 Bottom line

Without Timescale: you manage partitions, materialized view refresh, and partition rotation jobs yourself. Works fine up to ~100–200 users.

With Timescale: you get automatic rollups, compression, TTL, and better scaling as results grow into billions of rows. Makes ops simpler, lets you keep longer history, and keeps dashboards fast.