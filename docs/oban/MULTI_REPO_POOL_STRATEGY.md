# Oban Multi-Repo Pool Strategy

**Topic**: Separate repos for connection pool isolation (performance), shared migrations (simplicity)
**Date**: 2025-10-19
**Status**: Implemented ✅
**Key Point**: Two repos = better performance, NOT code organization

---

## Problem: Connection Pool Starvation

In a monitoring SaaS with high job throughput:
- Oban processes 1000+ checks per second
- App queries need instant response
- Single shared pool = jobs starve app requests ❌

**Example - Single Pool (BAD)**:
```
Connection Pool (10 connections)
├─ 8 connections → Oban job processing (monitor checks)
└─ 2 connections → App queries (user dashboard stuck!)

Result: Dashboard slow, users frustrated 😱
```

---

## Solution: Separate Connection Pools (Same Database)

### Architecture

```
PostgreSQL Database (single DATABASE_URL)
│
├─ public schema
│  └─ app_schema_migrations (tracks all migrations)
│
├─ app schema
│  ├─ users
│  ├─ monitors
│  ├─ incidents
│  ├─ alerts
│  ├─ status_pages
│  └─ regions
│
└─ oban schema
   ├─ oban_jobs
   ├─ oban_peers
   ├─ oban_completed_jobs
   └─ oban_discarded_jobs
```

### Repos Configuration

```elixir
# Two Ecto repos, same database, separate pools
config :uptrack,
  ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo]

# AppRepo: Handles all migrations
config :uptrack, Uptrack.AppRepo,
  url: "postgresql://uptrack:pass@localhost/uptrack_prod",
  pool_size: 10,           # App queries
  migration_lock: :pg_advisory_lock

# ObanRepo: Same database, larger pool
config :uptrack, Uptrack.ObanRepo,
  url: "postgresql://uptrack:pass@localhost/uptrack_prod",
  pool_size: 20            # Job processing
```

---

## Design Decisions

### ✅ Two Separate Repos (Performance)

**Why keep two repos?**

**ONLY reason: Connection Pool Isolation = Better Performance**

1. **App queries get dedicated pool** (10-15 connections)
   - User-facing, must be responsive
   - Fast response time critical

2. **Job processing gets separate pool** (20-30 connections)
   - Background processing, tolerates latency
   - Can consume many connections without hurting users

3. **No resource competition**
   - High Oban load doesn't block app queries
   - App peak load doesn't starve job processing
   - Both can scale independently

**NOT for code organization:**
- Both connect to same database
- Schema separation has no performance benefit
- It's just code clarity

### ✅ Single Migration Source (Simplicity)

**Why share migrations in AppRepo?**

1. **One migration command**: `mix ecto.migrate`
2. **One migration table**: `app_schema_migrations`
3. **App + Oban deploy together** (atomic)
4. **No coordination needed**

### ❌ Not Three Repos

Why remove ResultsRepo?

1. **ClickHouse replaces time-series data** (via `ch` library + ResilientWriter)
2. **Reduces configuration** (no third pool to tune)
3. **Keeps Oban lean** (no bloated results tables)

---

## Migration Structure

### Before (Complex)

```
priv/
├─ app_repo/migrations/           # App schema
│  ├─ 20250923155001_create_users.exs
│  └─ 20250923155002_add_regions.exs
├─ oban_repo/migrations/          # Oban schema
│  └─ 20250923102216_initial_setup.exs
└─ results_repo/migrations/       # DELETED (not needed)
   └─ 20250923102216_initial_setup.exs

Migration tables: 3
- app_schema_migrations
- oban_schema_migrations
- results_schema_migrations
```

### After (Simple)

```
priv/
├─ app_repo/migrations/           # All migrations
│  ├─ 20250923155001_create_users.exs
│  ├─ 20250923155002_add_regions.exs
│  └─ 20250923102216_create_oban_schema.exs
└─ repo/
   └─ seeds.exs

Migration tables: 1
- app_schema_migrations
```

### Oban Migration (Moved to AppRepo)

```elixir
# priv/app_repo/migrations/20250923102216_create_oban_schema.exs
defmodule Uptrack.Repo.Migrations.CreateObanSchema do
  use Ecto.Migration

  def up do
    # Create oban schema
    execute("CREATE SCHEMA IF NOT EXISTS oban")

    # Install Oban tables in oban schema
    Oban.Migration.up(prefix: "oban", version: 12)
  end

  def down do
    Oban.Migration.down(prefix: "oban", version: 1)
    execute("DROP SCHEMA IF EXISTS oban CASCADE")
  end
end
```

---

## Connection Pool Behavior

### App Queries

```elixir
# AppRepo pool (size: 10)
user = Uptrack.AppRepo.get!(User, user_id)        # ✅ Gets dedicated pool
incident = Uptrack.AppRepo.insert!(incident)      # ✅ Doesn't wait for jobs
```

### Job Processing

```elixir
# ObanRepo pool (size: 20)
# Oban uses separate pool, doesn't affect app
Uptrack.ObanRepo.insert_all(Oban.Job, jobs)       # Uses ObanRepo pool

# In background:
Uptrack.Oban.check_monitor_job.perform(%{monitor_id: "123"})
  # Uses ObanRepo pool
  # App queries still responsive
```

---

## Configuration Per Environment

### Production

```bash
# DATABASE_URL: Single PostgreSQL primary
DATABASE_URL=postgresql://uptrack:pass@germany-primary:5432/uptrack_prod

# Pool sizes for Germany node (primary, handles all writes)
APP_POOL_SIZE=15      # More connections for heavy user load
OBAN_POOL_SIZE=30     # Large pool for 1000+ checks/sec across 5 regions
```

### Staging

```bash
DATABASE_URL=postgresql://uptrack:pass@staging-db:5432/uptrack_staging

# Smaller pools in staging
APP_POOL_SIZE=5
OBAN_POOL_SIZE=10
```

### Development

```bash
DATABASE_URL=postgresql://uptrack:pass@localhost:5432/uptrack_dev

# Minimal pools in dev
APP_POOL_SIZE=5
OBAN_POOL_SIZE=10
```

---

## Migration Running

### Running Migrations

```bash
# Runs all AppRepo migrations (includes Oban schema setup)
mix ecto.migrate

# Or explicitly:
mix ecto.migrate -r Uptrack.AppRepo

# Creates/updates:
# - app schema tables
# - oban schema tables (via Oban.Migration.up)
# - Tracks in public.app_schema_migrations
```

### Rollback

```bash
# Rollback latest AppRepo migration
mix ecto.rollback

# This could roll back either:
# - An app table change
# - An oban table change
# (depends on what the latest migration did)
```

---

## Benefits

| Aspect | Benefit |
|--------|---------|
| **Pool isolation** | App queries never starved by jobs |
| **Single migrations** | Cleaner than managing 3 migration tables |
| **Deployment** | App and Oban deploy together naturally |
| **Clarity** | No confusion about schema ownership |
| **Maintenance** | Easier to understand and debug |
| **Simplicity** | Removed unnecessary complexity |

---

## Tradeoffs

| Tradeoff | Impact |
|----------|--------|
| **Two repos** | Slightly more config than one repo |
| **Same database** | No physical isolation (but not needed) |
| **AppRepo migrations** | Changes app and oban tables together |

**Decision**: Tradeoffs are worth it. The isolation benefit > config complexity.

---

## Schema Documentation

### App Schema

Tables managed by application code:

- `users` - User accounts
- `monitors` - Monitor configurations
- `incidents` - Alert incidents
- `alerts` - Alert definitions
- `status_pages` - Public status pages
- `regions` - Geographic regions
- `monitor_regions` - Monitor-to-region mapping

### Oban Schema

Tables managed by Oban library:

- `oban_jobs` - Job queue (active jobs)
- `oban_peers` - Node membership (for distributed processing)
- `oban_completed_jobs` - Completed job history
- `oban_discarded_jobs` - Failed jobs

### Migration Table

- `app_schema_migrations` - Tracks all migrations (app + oban)

---

## Code Changes

### config/config.exs
```elixir
# Before
ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo, Uptrack.ResultsRepo]

config :uptrack, Uptrack.AppRepo,
  migration_source: "app_schema_migrations"

config :uptrack, Uptrack.ObanRepo,
  migration_source: "oban_schema_migrations"

config :uptrack, Uptrack.ResultsRepo,
  migration_source: "results_schema_migrations"

# After
ecto_repos: [Uptrack.AppRepo, Uptrack.ObanRepo]

config :uptrack, Uptrack.AppRepo,
  migration_lock: :pg_advisory_lock
```

### config/runtime.exs
```elixir
# Before
app_database_url = System.get_env("DATABASE_URL")
oban_database_url = System.get_env("OBAN_DATABASE_URL")
results_database_url = System.get_env("RESULTS_DATABASE_URL")

app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")
results_pool_size = String.to_integer(System.get_env("RESULTS_POOL_SIZE") || "15")

# After
database_url = System.get_env("DATABASE_URL")

app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")

config :uptrack, Uptrack.AppRepo,
  url: database_url,
  pool_size: app_pool_size

config :uptrack, Uptrack.ObanRepo,
  url: database_url,
  pool_size: oban_pool_size
```

### mix.exs
```elixir
# Before
"ecto.setup": [
  "ecto.create",
  "ecto.migrate -r Uptrack.AppRepo",
  "ecto.migrate -r Uptrack.ObanRepo",
  "ecto.migrate -r Uptrack.ResultsRepo",
  "run priv/repo/seeds.exs"
]

# After
"ecto.setup": [
  "ecto.create",
  "ecto.migrate -r Uptrack.AppRepo",
  "run priv/repo/seeds.exs"
]
```

---

## Testing

Setup sandbox for both repos:

```elixir
# test/support/data_case.ex
def setup_sandbox(tags) do
  app_pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Uptrack.AppRepo, shared: not tags[:async])
  oban_pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Uptrack.ObanRepo, shared: not tags[:async])

  on_exit(fn ->
    Ecto.Adapters.SQL.Sandbox.stop_owner(app_pid)
    Ecto.Adapters.SQL.Sandbox.stop_owner(oban_pid)
  end)
end
```

---

## Summary

**Final Architecture**:

```
PostgreSQL (single URL)
├─ AppRepo (pool: 10-15)    ← App queries
└─ ObanRepo (pool: 20-30)   ← Job processing

Migrations:
├─ AppRepo owns all migrations
├─ Oban schema created during migration
└─ Single app_schema_migrations table tracks everything

ClickHouse (via ch + ResilientWriter):
└─ Time-series monitoring data (separate from Postgres)
```

**Key Points**:
- ✅ Two repos = pool isolation
- ✅ One migration source = simpler
- ✅ Single DATABASE_URL = less config
- ✅ App + Oban deploy together = natural cadence
- ✅ ClickHouse separate = optimal for time-series

**Result**: Clean, simple, performant architecture.
