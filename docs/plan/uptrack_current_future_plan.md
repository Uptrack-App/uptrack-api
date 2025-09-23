# Uptrack Infrastructure Plan — Current vs Future

This document outlines the **current launch plan** for Uptrack on Hetzner Cloud at ~$50/mo, and the **future evolution** to full high availability (HA) and scalability with minimal downtime.

---

## 🌱 Current Plan (Phase 1)

### Goals
- True HA for **App tier** only (stateless nodes behind a load balancer).
- Single Postgres database with **3 schemas**: `app`, `oban`, `results`.
- TimescaleDB enabled in `results` schema for history retention.
- Simple & cheap, but **DB is a single point of failure** (backups mitigate risk).

### Hetzner Infrastructure
- **Load Balancer**: Hetzner LB (routes to healthy app nodes).
- **App tier**: 2 × CPX11 (1 vCPU, 2GB RAM) — Phoenix API + Oban workers.
- **Database**: 1 × CPX21 (2 vCPU, 4GB RAM) — Postgres + TimescaleDB (all schemas).
- **Backups**: Hetzner Storage Box (WAL archiving + nightly base backup).

### Repos & Schemas
- **AppRepo → `app` schema** (tenants, monitors, incidents, billing).
- **ObanRepo → `oban` schema** (job orchestration, PgBouncer SESSION).
- **ResultsRepo → `results` schema** (Timescale hypertables, rollups).

### Data Management
- **Hypertables**:
  - `monitor_results_paid` → 365d retention, compress after 7d.
  - `monitor_results_free` → 180d retention, compress after 7d.
- **Continuous aggregates**:
  - 1-minute rollup (3–14d window).
  - 5-minute rollup (90–180d window).
  - Daily rollup (up to 2 years).
- **Dashboards** always query aggregates, not raw hypertables.

### Capacity
- Supports ~100 paid + 500 free users (with required history).
- Disk footprint manageable (<200 GB compressed).
- DB outage = downtime until restore (~10–15 min RTO).

---

## 🚀 Future Plan (Painless Migration to HA)

### Phase 2 — Database HA (~$90–130/mo)
- Migrate AppRepo + ObanRepo to **HA Postgres cluster** (Patroni or Managed PG).
- Add HAProxy/PgBouncer for unified writer endpoint.
- ResultsRepo can stay on same DB or move later.
- **App change required:** none (just flip `*_DATABASE_URL` env vars).

### Phase 3 — Results Scale-out (~$150–200/mo)
- Move ResultsRepo to a **dedicated Timescale cluster** (larger VM, optional replicas).
- Retention + compression policies keep storage costs predictable.
- **App change required:** none (flip `RESULTS_DATABASE_URL`).

### Phase 4 — Horizontal Growth (> $300/mo)
- App DB sharding with **Citus** (shard by `account_id`).
- Optional multi-region HA with **Yugabyte** or cross-region PG.
- Scale workers horizontally (more app nodes).
- Optionally offload heavy analytics to **ClickHouse**.

---

## 🛡️ Guardrails for Painless Migration
- Always use **3 repos** (AppRepo, ObanRepo, ResultsRepo), even if pointing to the same DB initially.
- Separate schemas in DB for clean migration.
- Idempotent jobs with unique keys (safe retries).
- Store response bodies/blobs in object storage, not DB.
- Use jitter + rate limiting in schedulers to smooth load.
- DSNs configurable via env vars only.

---

## ✅ Summary
- **Current (~$50):** App HA (2 nodes + LB), single DB with 3 schemas (Timescale for results), backups for recovery.  
- **Future (~$90–200):** Add DB HA, move results to dedicated cluster, scale horizontally — all with **env var flips only, no downtime**.  
- This ensures you start lean, but can scale to **1,000+ users** and **1 year of history** without re-architecture.
