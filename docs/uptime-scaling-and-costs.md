# Uptime Monitoring: Technical Challenge, Capacity, and Cost-Efficient Stack

## Problem Statement
- Monitor uptime for many tenants. Example: 1,000 users × 100 monitors each, every minute.
- Each monitor issues a probe (HTTP/TCP/ping/keyword) and stores a result, triggers alerts on state changes, and powers dashboards.
- Constraints given: single node with ~1 GB RAM and 1 vCPU (starter tier).

## Key Constraints and Bottlenecks
- Network I/O: outbound HTTP/TCP dominates latency; CPU is secondary.
- Database writes: if every probe produces a row, write rate becomes the primary bottleneck.
- Memory: unnecessary buffering or large response bodies inflate memory usage.
- Burstiness: running many checks at the same second creates spikes in HTTP and DB load.

## Capacity Estimate (single node, 1 GB RAM, 1 vCPU)
- Checks/minute = users × 100.
- Concurrency needed ≈ arrival_rate × average_latency.
  - With ~300 ms average HTTP latency, 10k checks/min ≈ 167/s ⇒ ~50 concurrent requests.
- Practical envelope on such a node (with Postgres on modest hardware):
  - Comfortable: 6k–12k checks/min (100–200 inserts/s).
  - Pushing: 20k–30k checks/min (300–500 inserts/s) with careful tuning and reduced payloads.
  - 100k checks/min (1k users × 100) typically requires multi-node workers and a stronger DB or different write model.

Conclusion: Elixir/BEAM is sufficient on a single node for roughly 60–120 users (each with 100 monitors @ 1/min). Beyond that, plan to scale horizontally and/or change the storage model.

## Recommended Baseline Architecture (Elixir‑only)
- App: Phoenix + Bandit (already used).
- HTTP client: `Req` with connection pooling; set conservative timeouts per monitor.
- Workers: `Task.Supervisor` or `Task.async_stream/3` for bounded concurrency and back-pressure.
- Scheduler: a GenServer that spreads work evenly with jitter; avoid minute-bound bursts.
- Storage: Postgres with a skinny `monitor_checks` table and strict retention.
- PubSub + Alerting: Phoenix.PubSub for fanout; async alert delivery to avoid blocking probes.

Why Elixir (no Rust) is enough here: the workload is I/O + storage bound. BEAM handles tens to hundreds of concurrent probes on 1 vCPU; DB throughput and data volume are the true limits.

## Data Model and Retention (cost + performance)
- Store less by default:
  - Only persist state changes (up → down, down → up) + periodic rollups (e.g., 1 sample/min or 5‑min aggregates).
  - Keep error snippets, not full bodies; cap text fields to small sizes.
  - Prefer `HEAD` for simple uptime checks; fall back to `GET` only when needed.
- Table design:
  - Narrow columns: `status`, `status_code`, `response_time`, `checked_at`, short `error_message`.
  - Avoid large `response_body` except on demand or sampled.
  - Index minimally: `(monitor_id, checked_at DESC)` and maybe partial index on `status = 'down'`.
- Retention:
  - Raw rows: 7–14 days (configurable).
  - Aggregates: 30–180 days.
  - Use scheduled jobs to prune old partitions/buckets.

## Scheduling and Concurrency
- Jitter: spread checks uniformly across the minute to smooth load.
- Concurrency cap: bound with `Task.async_stream/3` (e.g., 32–64 concurrent) and tune using latency and CPU headroom.
- Timeouts: set per-monitor timeout; fail fast to prevent pileups.
- Back-pressure: if backlog grows, skip non-critical body capture and prioritize status-only probes.

## Alerting Strategy
- Trigger alerts only on state transitions (and optionally on sustained failures via thresholding).
- Debounce: require N consecutive failures or a minimum duration before “down”.
- Notifications: async delivery; retries with exponential backoff; dead-letter queue for failed webhooks.

## Cheapest Practical Stack Options
These focus on minimizing total cost while staying reliable. Prices vary by provider and time; compare before choosing.

- Single VM (cheapest starting point)
  - Run Phoenix app + Postgres on the same small VM.
  - Pros: lowest monthly cost, lowest network latency, simplest ops.
  - Cons: shared contention; must keep retention tight and payloads small.
  - Suitability: up to ~6k–12k checks/min comfortably if tuned.

- Single VM (app) + managed Postgres (budget tier)
  - App on a small VM; DB on the provider’s budget managed tier.
  - Pros: easier backups, less ops toil; DB can be scaled separately.
  - Cons: higher cost than single-box; network hop to DB (latency negligible for this use case).
  - Suitability: 10k–30k checks/min with DB tuned and data minimized.

- Two cheap VMs (split app and DB)
  - Self-host both app and Postgres on small VMs.
  - Pros: still inexpensive; isolates DB CPU/IO from app.
  - Cons: you own backups/monitoring; still need retention.

- Time-series alternative (optional)
  - If you must keep more raw data cheaply: consider a single-binary time-series DB (e.g., VictoriaMetrics) for probe results, keep relational data in Postgres.
  - Pros: high write throughput, simple retention policies.
  - Cons: added complexity; evaluate ops overhead vs. benefit.

Notes on providers:
- Value leaders for small VMs are often regional cloud/VPS providers (e.g., Hetzner, Contabo) and commodity VPS (e.g., Vultr, Linode/Akamai, DigitalOcean). Pick based on region, bandwidth, and included snapshots.
- Free/always‑free tiers (e.g., some cloud providers) can be used for small Postgres instances, but reliability varies; test durability and backup story.

## When You Need More Than One Node
- Target: 100k checks/min (1k users × 100 @ 1/min) generally needs:
  - Multiple worker nodes (e.g., 10–20 small VMs) sharded by monitor ID hash.
  - A stronger Postgres with partitioning or a time-series DB for raw probes.
  - A persistent job queue (e.g., Oban) to smooth spikes and coordinate retries (optional for smallest cost, helpful at scale).

## Cost Levers That Matter Most
- Store less data (biggest lever): state changes + rollups instead of every probe row.
- Add jitter to smooth load; lowers peak DB/HTTP concurrency requirements.
- Cap concurrency and timeouts based on observed latency; avoid thundering herds.
- Keep tables skinny; avoid storing response bodies by default.
- Retain raw data for days, not months; keep long-term aggregates only.

## Concrete Targets for a 1 GB / 1 vCPU Node
- Max concurrent probes: 32–64 (tune empirically).
- Probe timeout: 5–10 s default; per-monitor override.
- DB inserts: aim ≤ 200/s steady-state; use bulk insert/batching if you insist on every probe row.
- Retention: raw 7–14 days; aggregates 90 days.
- Jitter: randomize schedule across the minute (uniformly).

## Rust or NIFs?
- Not needed for the baseline. They won’t meaningfully change network or DB bottlenecks.
- Consider only for specialized CPU-bound tasks (e.g., custom TLS parsing, compression) kept under dirty-scheduler limits.

## Roadmap to Scale Up Cheaply
1. Start with a single VM running app + Postgres, strict retention, no bodies.
2. Add jitter + concurrency caps; measure p95 latency and DB CPS (commits/sec).
3. If DB is the limit, switch to state-change storage + minute aggregates.
4. Split DB/app onto separate small VMs or move DB to a budget managed tier.
5. For 30k+ checks/min, shard workers across a few VMs; keep retention tight.
6. For 100k+/min, introduce a time-series store for raw probes or heavily partition Postgres; use a queue for work distribution.

## Summary
- Elixir on a tiny node can handle roughly 6k–12k checks/min sustainably with careful scheduling, tight retention, and skinny rows — about 60–120 users with 100 monitors each.
- The cheapest stack is a single small VM (Phoenix + Postgres), evolving to separate app/DB boxes or a budget managed DB as load grows.
- Your main cost and performance levers are data volume (what you store), jitter, concurrency caps, and retention.

