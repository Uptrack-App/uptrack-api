# Zero-Downtime Scaling Roadmap (Startup-Friendly)

This roadmap shows how to start as cheaply as possible and scale to high volume without interrupting users. It focuses on Elixir/Phoenix workers, Postgres storage, jittered scheduling, and state-change + aggregates persistence.

## Principles
- Smooth load: jitter schedules so checks are uniformly distributed across the minute.
- Store less: write state-changes + rollups, avoid bodies; keep raw retention short.
- Backward-compatible changes: migrations are additive-first; backfill; then switch reads/writes.
- Rolling changes: update one node at a time behind a load balancer.
- Observe first: measure p95 latency, DB commits/sec, queue depth, NIC egress before scaling.

## Phase 0 — Cheapest Start (Single VPS)
- One VPS (2 vCPU, 4 GB, NVMe): run Phoenix + Postgres on the same box.
- Targets: ~10k–15k monitors @ 1/min (state-changes + aggregates).
- Backups: weekly provider snapshots; daily `pg_dump` to object storage.

Operational notes
- Use `Req` with modest concurrency caps (e.g., 32–64) and short timeouts (5–10s).
- Enable jitter (random or deterministic hash over monitor_id).
- Postgres: daily partitions, `(monitor_id, checked_at DESC)` index, partial index on `status='down'`.

## Phase 1 — Split DB (Zero/near-zero downtime)
Goal: move Postgres to its own small VPS (or budget managed tier) without downtime.

Cutover plan
1) Provision new Postgres (same major version), enable WAL archiving and `wal_compression=on`.
2) Seed data: `pg_basebackup` (or `pg_dump` + restore for small DB). Start as replica (physical or logical replication).
3) Keep app writing to old DB; let new DB catch up (replication).
4) Flip connections:
   - Lower DNS TTL for DB hostname to 60s ahead of time.
   - Update app DB URL to the new host, deploy rolling (or restart one node at a time).
   - If using PGBouncer, point it at the new DB first, then apps remain pointed at PGBouncer.
5) Keep old DB as read-only for a day; decommission after validation.

Expected impact: a few brief connection churns masked by pool retries. LiveView sessions survive via reconnects.

## Phase 2 — Add Web/API Node + Load Balancer
Goal: high-availability UI/API without downtime.

Steps
- Add a second app node (same image). Place both behind a simple TCP/WebSocket-capable load balancer (provider LB, HAProxy, or Nginx).
- Use Phoenix cookies (stateless sessions). No sticky sessions required.
- PubSub: ensure node discovery (e.g., `DNSCluster`) so LiveView broadcasts reach all nodes.
- Rolling deploys: drain, deploy, rejoin. Deploy one node at a time.

## Phase 3 — Introduce Worker Shards (Check Executors)
Goal: scale check throughput independently of the UI.

Options
- Elixir workers: run headless worker nodes with scheduler enabled; web nodes run scheduler disabled.
- Deterministic sharding: hash(monitor_id) → shard; each worker claims a shard range. Alternatively, use a job queue (e.g., Oban) to distribute work.
- Zero-downtime switch:
  1) Add code paths that honor `SCHEDULER_ENABLED` flag.
  2) Boot first worker node with scheduler on; web nodes keep it off.
  3) Scale workers horizontally; each new worker claims its shard range.

## Phase 4 — DB Hardening
Goal: keep storage fast and cheap while growing.

- Partitioning: daily partitions for `monitor_checks`; scheduled job drops old partitions.
- Online indexes: use `CREATE INDEX CONCURRENTLY` in migrations to avoid table locks.
- Backfills: perform in batches (e.g., 5–10k rows/commit) with `NOWAIT/SKIP LOCKED` patterns.
- Aggregates: maintain minute/hour rollups; dashboards query aggregates, not raw.
- Connection pooling: add `pgbouncer` in transaction mode; keep Ecto pools modest (20–50).

## Phase 5 — Move to Managed Postgres (Optional)
Goal: outsource DB ops with minimal/no downtime.

- Provision managed Postgres; set up logical replication from self-hosted to managed.
- Catch up; then flip app connections (rolling) to the managed endpoint.
- Keep old DB read-only for fallback; decommission after validation.

## Phase 6 — Regional Worker Pools (Optional)
Goal: minimize latency and egress by running workers near targets.

- Add small worker pools in key regions. All write to the same central Postgres (or via a queue).
- Jitter remains deterministic; shards assigned per region.
- Keep UI centralized or add a read replica for queries if needed.

## Zero-Downtime Migration Patterns
- Additive-first schema changes:
  1) Add new columns/tables nullable.
  2) Dual-write (old + new) under a feature flag.
  3) Backfill in batches.
  4) Flip reads to the new path.
  5) Remove old fields in a later deploy.
- Indexes: `CREATE INDEX CONCURRENTLY`; drop with `DROP INDEX CONCURRENTLY`.
- Background work: rate-limit backfills; avoid impacting probe writes.

## Operational Guardrails
- Health checks per node (HTTP + custom probe queue depth).
- Alerting on p95 latency, DB CPS, WAL size, disk IOPS, and backlog size.
- Strict retention (raw 7–14 days; aggregates 90–180 days).
- Runbooks for rollbacks: keep the previous release image; maintain DB snapshots.

## Decision Checklist (When to Scale)
- p95 probe latency or timeouts are rising at current concurrency → add worker node(s).
- DB commits/sec or I/O saturation → tune queries; add partitions; consider splitting app/DB or upgrading DB box.
- UI latency or websocket disconnects under load → add a web/API node and a load balancer.

## FAQ
- Do we need sticky sessions? No (Phoenix signed cookies). Ensure LB/WebSocket support.
- Will LiveView drop on deploy? Briefly reconnects; do rolling deploys to keep at least one node available.
- How to avoid duplicate checks across nodes? Use sharding or a queue that enforces uniqueness; keep scheduler off on web nodes.

---
This roadmap keeps changes incremental and reversible. Start with one VPS, split the DB, add a second app node, then scale workers and harden the DB — all with rolling changes and backward-compatible migrations.

