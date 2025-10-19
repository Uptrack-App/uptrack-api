# Oban + ClickHouse: Pooling & Migration Strategy

**Date**: 2025-10-19
**Topic**: Optimizing Oban configuration with ClickHouse and multi-repo pooling
**Status**: Analysis & Recommendations

---

## Current Setup Analysis

### Multi-Repo Architecture

```elixir
# 3 separate database repos
ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo, Uptrack.ResultsRepo]

AppRepo:
  - PostgreSQL (users, monitors, incidents, alerts, status_pages)
  - Separate migrations: "app_schema_migrations"
  - Pool size: configurable per environment

ObanRepo:
  - PostgreSQL (Oban job queue)
  - Separate migrations: "oban_schema_migrations"
  - Oban primary connection

ResultsRepo:
  - PostgreSQL (results/monitoring data)
  - Separate migrations: "results_schema_migrations"
  - Pool size: configurable

ClickHouse:
  - Not an Ecto repo (HTTP API via Req)
  - Monitoring data: checks_raw table
  - Via ResilientWriter (batching + spooling)
```

### Questions You Asked

1. ✅ **Use ClickHouse with Oban** - Already doing this!
2. ✅ **Different pooling for Oban** - Already implemented!
3. ❓ **Reuse migrations** - This needs discussion

---

## Current Oban Pooling Setup (GOOD!)

### Production Configuration (runtime.exs)

```elixir
# Single POOL_SIZE applies to all 3 repos
pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

# AppRepo: 10 connections
config :uptrack, Uptrack.AppRepo,
  pool_size: pool_size

# ObanRepo: 10 connections (SEPARATE!)
config :uptrack, Uptrack.ObanRepo,
  pool_size: pool_size

# ResultsRepo: 10 connections (SEPARATE!)
config :uptrack, Uptrack.ResultsRepo,
  pool_size: pool_size

# Oban configuration
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,  # Uses ObanRepo, not AppRepo
  queues: [
    checks: 50,           # Concurrent check workers
    webhooks: 10,
    incidents: 5
  ]
```

✅ **You ARE using separate pooling!** Each repo has its own connection pool.

---

## Recommended Improvements

### Option 1: Different Pool Sizes per Repo (RECOMMENDED)

```elixir
# In config/runtime.exs

if config_env() == :prod do
  # Different pool sizes for different workloads
  app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
  oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")
  results_pool_size = String.to_integer(System.get_env("RESULTS_POOL_SIZE") || "15")

  # AppRepo: Light OLTP (users, configs, incidents)
  config :uptrack, Uptrack.AppRepo,
    url: app_database_url,
    pool_size: app_pool_size,  # Lower: light transactional
    queue_target: 50,
    queue_interval: 5000

  # ObanRepo: High concurrency job queue
  config :uptrack, Uptrack.ObanRepo,
    url: oban_database_url,
    pool_size: oban_pool_size,  # Higher: many concurrent jobs
    queue_target: 100,
    queue_interval: 1000

  # ResultsRepo: Bulk inserts (monitor checks)
  config :uptrack, Uptrack.ResultsRepo,
    url: results_database_url,
    pool_size: results_pool_size,  # Medium: batch writes
    queue_target: 75,
    queue_interval: 2000
end
```

**Environment Setup:**
```bash
# Germany (PostgreSQL primary)
export APP_POOL_SIZE=15      # More app connections (shared across 3 regions)
export OBAN_POOL_SIZE=30     # Many job workers (monitor checks)
export RESULTS_POOL_SIZE=20  # Batch monitor data writes

# India (replica)
export APP_POOL_SIZE=10      # Fewer: read-only
export OBAN_POOL_SIZE=25     # Many: still doing checks
export RESULTS_POOL_SIZE=15  # Batch writes to Austria CH
```

**Benefits:**
- ✅ Oban gets more connections (50+ concurrent checks)
- ✅ Results get balanced pool (bulk inserts)
- ✅ App pool stays reasonable (light queries)
- ✅ Control per environment

---

### Option 2: Use Queue-Based Limits (Alternative)

Instead of pool_size, limit concurrency at Oban level:

```elixir
# config/runtime.exs
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  queues: [
    checks: 75,       # Run 75 concurrent check workers
    webhooks: 15,
    incidents: 10
  ],
  limit: 100         # Global limit across all queues
```

**How this works:**
- Oban uses connection pool on-demand
- Workers wait if pool exhausted
- Better resource control

---

## ClickHouse Integration (You're Doing This Right!)

### Current Setup (GOOD!)

```elixir
# Via ResilientWriter
# - Batches 200 rows per batch
# - Async HTTP POST to ClickHouse
# - Spools to disk if ClickHouse down

ResilientWriter.write_check_result(%{
  monitor_id: uuid,
  status: "up",
  response_time_ms: 123,
  region: "us-east"
})
```

**Separation:**
- **PostgreSQL**: Transactional data (via Ecto repos)
- **ClickHouse**: Time-series data (via HTTP + ResilientWriter)
- **No conflicts!**

---

## Migration Strategy: Reuse or Separate?

### Current Approach: SEPARATE (CORRECT!)

```elixir
# config/config.exs
config :uptrack, Uptrack.AppRepo,
  migration_source: "app_schema_migrations"

config :uptrack, Uptrack.ObanRepo,
  migration_source: "oban_schema_migrations"

config :uptrack, Uptrack.ResultsRepo,
  migration_source: "results_schema_migrations"
```

**Why separate:**
✅ Prevents migration conflicts
✅ Clear ownership (app vs jobs vs results)
✅ Independent versioning
✅ Easier rollback per repo

### Why NOT Reuse Migrations

**Problem with shared migrations:**
```
app_repo/migrations/
├── 20250923_create_users.exs
├── 20250923_create_oban_jobs.exs  ❌ Mixed!
└── 20250923_create_results.exs    ❌ Mixed!
```

If one fails, all fail. If you need different timings per repo, you can't.

---

## Configuration Update: RECOMMENDED

### Update `config/runtime.exs`

```elixir
if config_env() == :prod do
  app_database_url = System.get_env("DATABASE_URL") || raise "..."
  oban_database_url = System.get_env("OBAN_DATABASE_URL") || raise "..."
  results_database_url = System.get_env("RESULTS_DATABASE_URL") || raise "..."

  # Pool size differentiation
  app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
  oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")
  results_pool_size = String.to_integer(System.get_env("RESULTS_POOL_SIZE") || "15")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # AppRepo: Light OLTP workload
  config :uptrack, Uptrack.AppRepo,
    url: app_database_url,
    pool_size: app_pool_size,
    queue_target: 50,
    queue_interval: 5000,
    socket_options: maybe_ipv6

  # ObanRepo: High job throughput
  config :uptrack, Uptrack.ObanRepo,
    url: oban_database_url,
    pool_size: oban_pool_size,
    queue_target: 100,
    queue_interval: 1000,
    socket_options: maybe_ipv6

  # ResultsRepo: Batch inserts
  config :uptrack, Uptrack.ResultsRepo,
    url: results_database_url,
    pool_size: results_pool_size,
    queue_target: 75,
    queue_interval: 2000,
    socket_options: maybe_ipv6

  # Oban with node-specific config
  config :uptrack, Oban,
    repo: Uptrack.ObanRepo,
    node: System.get_env("OBAN_NODE_NAME", "unknown-node"),
    queues: [
      checks: String.to_integer(System.get_env("OBAN_CHECKS_CONCURRENCY", "50")),
      webhooks: String.to_integer(System.get_env("OBAN_WEBHOOKS_CONCURRENCY", "10")),
      incidents: String.to_integer(System.get_env("OBAN_INCIDENTS_CONCURRENCY", "5"))
    ],
    plugins: [
      {Oban.Plugins.Pruner, max_age: 604_800},
      Oban.Plugins.Repeater,
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)},
      {Oban.Plugins.Cron, crontab: [
        {"*/30 * * * * *", Uptrack.Monitoring.SchedulerWorker}
      ]}
    ]
end
```

---

## Environment Variables Guide

### Germany Node (PostgreSQL PRIMARY)

```bash
# Connection strings
DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=app,public
OBAN_DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=oban,public
RESULTS_DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=results,public

# Pool sizes (handle all regions' jobs)
APP_POOL_SIZE=15
OBAN_POOL_SIZE=30
RESULTS_POOL_SIZE=20

# Node identification
OBAN_NODE_NAME=germany
NODE_REGION=eu-central

# Job concurrency
OBAN_CHECKS_CONCURRENCY=50
OBAN_WEBHOOKS_CONCURRENCY=10
OBAN_INCIDENTS_CONCURRENCY=5

# ClickHouse (Austria)
CLICKHOUSE_HOST=100.64.0.2
CLICKHOUSE_PORT=8123
```

### India Strong Node (PostgreSQL REPLICA)

```bash
# Connection strings (read from German primary)
DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=app,public
OBAN_DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=oban,public
RESULTS_DATABASE_URL=postgresql://uptrack:PASS@100.64.0.1:5432/uptrack_prod?search_path=results,public

# Pool sizes (lower: reading from replica in this region)
APP_POOL_SIZE=10
OBAN_POOL_SIZE=25
RESULTS_POOL_SIZE=15

# Node identification
OBAN_NODE_NAME=india-strong
NODE_REGION=ap-south

# Job concurrency (regional check workers)
OBAN_CHECKS_CONCURRENCY=40
OBAN_WEBHOOKS_CONCURRENCY=8
OBAN_INCIDENTS_CONCURRENCY=4

# ClickHouse
CLICKHOUSE_HOST=100.64.0.2
CLICKHOUSE_PORT=8123
```

---

## Summary: Your Questions Answered

### Q1: "How about using ClickHouse with Oban?"
**A**: You already are! Via ResilientWriter (batching + spooling). Perfect separation.

### Q2: "Different pooling with different repos but reuse migration?"
**A**:
- ✅ **DO**: Use different pool sizes per repo (recommended update above)
- ❌ **DON'T**: Reuse migrations - keep them separate (current setup is correct)

### Q3: "Update repo config"
**A**: See recommended config/runtime.exs changes above - adds per-repo pool sizing.

---

## Next Steps

1. **Test Current Setup**: Verify existing multi-repo pooling works
2. **Apply Pool Size Differentiation**: Use APP/OBAN/RESULTS_POOL_SIZE env vars
3. **Monitor in Production**: Watch connection usage per repo
4. **Document in .env.example**: Add new env vars

---

**Recommendation Level**: HIGH ⭐⭐⭐
**Risk**: LOW (backward compatible)
**Benefit**: Better resource utilization
