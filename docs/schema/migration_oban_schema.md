# Oban Schema Migration (oban schema)

**Status**: Using Ecto migration (AppRepo manages all migrations)
**Reference**: See `/priv/app_repo/migrations/20250923102216_create_oban_schema.exs`

---

## Current Approach (Uptrack)

Oban schema is created through Ecto migration in AppRepo:

```elixir
# priv/app_repo/migrations/20250923102216_create_oban_schema.exs
defmodule Uptrack.Repo.Migrations.CreateObanSchema do
  use Ecto.Migration

  def up do
    # Create oban schema
    execute("CREATE SCHEMA IF NOT EXISTS oban")

    # Install Oban tables in oban schema using Oban.Migration
    Oban.Migration.up(prefix: "oban", version: 12)
  end

  def down do
    Oban.Migration.down(prefix: "oban", version: 1)
    execute("DROP SCHEMA IF EXISTS oban CASCADE")
  end
end
```

Run with:
```bash
mix ecto.migrate
```

---

## Schema Structure (Auto-created by Oban.Migration)

Oban automatically creates these tables in the `oban` schema:

```sql
oban.jobs
├─ id (bigserial PRIMARY KEY)
├─ queue (text) - job queue name
├─ state (text) - pending, available, executing, completed, cancelled, discarded
├─ worker (text) - worker module
├─ args (jsonb) - job arguments
├─ errors (jsonb[]) - error history
├─ attempt (int) - current attempt
├─ max_attempts (int) - max retries
├─ inserted_at (timestamptz)
├─ scheduled_at (timestamptz)
├─ attempted_at (timestamptz)
├─ completed_at (timestamptz)
└─ attempted_by (text[]) - nodes that tried

oban.peers
├─ name (text PRIMARY KEY) - node name
├─ node (text) - Erlang node identifier
├─ expires_at (timestamptz) - heartbeat timestamp

oban.completed_jobs
└─ (same structure as jobs, but for history)

oban.discarded_jobs
└─ (same structure as jobs, but for failed jobs)
```

### Key Indexes (Auto-created)

```sql
-- For fetching jobs efficiently
CREATE INDEX oban_jobs_queue_state ON oban.jobs(queue, state);
CREATE INDEX oban_jobs_scheduled_at ON oban.jobs(scheduled_at);

-- For pruning old records
CREATE INDEX oban_jobs_inserted_at ON oban.jobs(inserted_at);
```

---

## Why AppRepo Manages Oban Migrations

### Benefits

1. **Single Migration Source**
   - One migration table: `app_schema_migrations`
   - No separate `oban_schema_migrations`
   - Simpler deployment

2. **Atomic Deployments**
   - App schema + Oban schema deployed together
   - No versioning conflicts
   - Single rollback point

3. **Clearer Ownership**
   - AppRepo owns all PostgreSQL schema changes
   - ObanRepo just uses the database (separate pool)
   - Not responsible for infrastructure setup

4. **Easier Debugging**
   - Single migration history to inspect
   - `mix ecto.migrations` shows all changes
   - No need to check multiple migration paths

---

## Configuration

### AppRepo (handles migrations)

```elixir
# config/runtime.exs
config :uptrack, Uptrack.AppRepo,
  url: "postgresql://user:pass@localhost/uptrack_prod",
  pool_size: 10,
  migration_lock: :pg_advisory_lock
```

### ObanRepo (uses same database, separate pool)

```elixir
# config/runtime.exs
config :uptrack, Uptrack.ObanRepo,
  url: "postgresql://user:pass@localhost/uptrack_prod",
  pool_size: 20
```

### Oban Configuration

```elixir
# config/config.exs
config :uptrack, Oban,
  repo: Uptrack.AppRepo,  # Uses AppRepo for migrations
  queues: [
    checks: 50,
    webhooks: 10,
    incidents: 5
  ],
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Repeater
  ]
```

---

## Manual Schema Creation (Reference Only)

If not using Ecto migrations, here's the raw SQL:

```sql
-- Create oban schema
CREATE SCHEMA IF NOT EXISTS oban;

-- Example: base jobs table (Oban.Migrations.up will create this and more)
CREATE TABLE oban.jobs (
    id bigserial PRIMARY KEY,
    queue text NOT NULL,
    state text NOT NULL,
    worker text NOT NULL,
    args jsonb NOT NULL,
    errors jsonb[] NOT NULL DEFAULT '{}',
    attempt int NOT NULL DEFAULT 0,
    max_attempts int NOT NULL DEFAULT 20,
    inserted_at timestamptz NOT NULL DEFAULT now(),
    scheduled_at timestamptz NOT NULL DEFAULT now()
);

-- Add required Oban indexes
CREATE INDEX oban_jobs_queue_state ON oban.jobs(queue, state);
CREATE INDEX oban_jobs_scheduled_at ON oban.jobs(scheduled_at);
```

---

## Related Documentation

- **Multi-Repo Strategy**: `/docs/oban/MULTI_REPO_POOL_STRATEGY.md`
- **Best Practices**: `/docs/oban/oban_migration_best_practices_with_author_recommend_refs.md`
- **Scaling Guide**: `/docs/oban/scale-oban.md`
