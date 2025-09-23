# Uptrack Current Plan with Painless Migration (ResultsRepo Focus)

This document explains the **current plan** for Uptrack’s infrastructure with emphasis on the **ResultsRepo** design, schema migration, and TimescaleDB configuration.  
It also includes retention policies for different user tiers: **Free, Solo, and Team**.

---

## 🌱 Current Plan (Phase 1 — ~$50/mo)

### Overview
- **App HA**: 2 × CPX11 app nodes + Hetzner Load Balancer.
- **Database**: 1 × CPX21 running Postgres + TimescaleDB.
  - Schemas: `app`, `oban`, `results`.
  - Oban uses PgBouncer in SESSION mode.
  - Results stored in Timescale hypertables for history.
- **Backup**: WAL archiving + nightly base backups to Hetzner Storage Box.

### Repos
- **AppRepo** → `app` schema.
- **ObanRepo** → `oban` schema.
- **ResultsRepo** → `results` schema (TimescaleDB).

Each repo has its own DSN (`APP_DATABASE_URL`, `OBAN_DATABASE_URL`, `RESULTS_DATABASE_URL`). Initially, all point to the same Postgres instance.

---

## 📂 ResultsRepo Design

### Hypertables
Results are split into **hypertables by user plan** so we can enforce different retention windows declaratively.

- `results.monitor_results_free` → Free tier (4 months = 120 days).
- `results.monitor_results_solo` → Solo tier (15 months ≈ 455 days).
- `results.monitor_results_team` → Team tier (15 months ≈ 455 days).

### Unified Read View
Expose a union view for convenience:

```sql
CREATE OR REPLACE VIEW results.monitor_results AS
SELECT * FROM results.monitor_results_free
UNION ALL
SELECT * FROM results.monitor_results_solo
UNION ALL
SELECT * FROM results.monitor_results_team;
```

### Suggested Schema
```sql
CREATE TABLE results.monitor_results_free (
    ts timestamptz NOT NULL,
    monitor_id bigint NOT NULL,
    account_id bigint NOT NULL,
    ok boolean NOT NULL,
    status_code int,
    err_kind text,
    total_ms int,
    probe_region text
);
SELECT create_hypertable('results.monitor_results_free','ts',
  chunk_time_interval => interval '1 day', if_not_exists => TRUE);

CREATE TABLE results.monitor_results_solo (LIKE results.monitor_results_free INCLUDING ALL);
SELECT create_hypertable('results.monitor_results_solo','ts',
  chunk_time_interval => interval '1 day', if_not_exists => TRUE);

CREATE TABLE results.monitor_results_team (LIKE results.monitor_results_free INCLUDING ALL);
SELECT create_hypertable('results.monitor_results_team','ts',
  chunk_time_interval => interval '1 day', if_not_exists => TRUE);
```

---

## ⚙️ TimescaleDB Config

### Compression
Enable compression for all hypertables, compressing after **7 days**:

```sql
ALTER TABLE results.monitor_results_free
  SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id');
ALTER TABLE results.monitor_results_solo
  SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id');
ALTER TABLE results.monitor_results_team
  SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id');

SELECT add_compression_policy('results.monitor_results_free', INTERVAL '7 days');
SELECT add_compression_policy('results.monitor_results_solo', INTERVAL '7 days');
SELECT add_compression_policy('results.monitor_results_team', INTERVAL '7 days');
```

### Retention Policies
- **Free tier**: 120 days (~4 months)
- **Solo tier**: 455 days (~15 months)
- **Team tier**: 455 days (~15 months)

```sql
SELECT add_retention_policy('results.monitor_results_free', INTERVAL '120 days');
SELECT add_retention_policy('results.monitor_results_solo', INTERVAL '455 days');
SELECT add_retention_policy('results.monitor_results_team', INTERVAL '455 days');
```

---

## 📊 Continuous Aggregates

### 1-minute rollup
```sql
CREATE MATERIALIZED VIEW results.mr_1m
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', ts) AS bucket,
       account_id, monitor_id,
       count(*) AS checks,
       sum((ok)::int) AS ok_count,
       avg(total_ms) AS avg_ms,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY total_ms) AS p95_ms
FROM results.monitor_results
GROUP BY bucket, account_id, monitor_id;

SELECT add_continuous_aggregate_policy('results.mr_1m',
  start_offset => INTERVAL '3 days',
  end_offset => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');
```

### 5-minute rollup
```sql
CREATE MATERIALIZED VIEW results.mr_5m
WITH (timescaledb.continuous) AS
SELECT time_bucket('5 minutes', ts) AS bucket,
       account_id, monitor_id,
       count(*) AS checks,
       sum((ok)::int) AS ok_count,
       avg(total_ms) AS avg_ms
FROM results.monitor_results
GROUP BY bucket, account_id, monitor_id;

SELECT add_continuous_aggregate_policy('results.mr_5m',
  start_offset => INTERVAL '180 days',
  end_offset => INTERVAL '5 minutes',
  schedule_interval => INTERVAL '5 minutes');
```

---

## 🔄 Painless Migration Path

- **Phase 1 (now):** All schemas in 1 Postgres node (CPX21).  
- **Phase 2:** Move `app` + `oban` schemas to HA Postgres (Patroni or Managed PG). Flip `APP_DATABASE_URL`, `OBAN_DATABASE_URL`.  
- **Phase 3:** Scale `results` by moving Timescale to its own VM/cluster. Flip `RESULTS_DATABASE_URL`.  
- **Phase 4:** Add replicas/shards if needed (Citus for app, ClickHouse for analytics).

**Key point:** because `ResultsRepo` is isolated, retention/rollups are applied transparently; migration only requires DSN changes.

---

## ✅ Summary

- **ResultsRepo** uses TimescaleDB with hypertables split by user tier.
- Retention policies:
  - Free: 120 days (4 months)
  - Solo: 455 days (15 months)
  - Team: 455 days (15 months)
- Compression after 7 days keeps storage efficient.
- Continuous aggregates provide fast dashboards.
- Migration later is painless: just flip DSNs.
