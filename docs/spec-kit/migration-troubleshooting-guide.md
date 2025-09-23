# Migration Troubleshooting Guide

## Overview

This guide addresses common issues encountered when setting up Uptrack's multi-repo database architecture and provides proven solutions.

## Problem: "Migrations already up" but schemas missing

### Symptoms
- `mix ecto.migrate` reports "Migrations already up"
- Database viewer shows only `app` schema
- Missing `oban` and `results` schemas
- Application errors referencing missing tables

### Root Cause
All three repositories (AppRepo, ObanRepo, ResultsRepo) share the same database and `schema_migrations` table. When AppRepo migration runs first, it marks the timestamp as "up" for all repos, preventing other repo migrations from executing.

### Solution Commands

#### Development Environment
```bash
# Force ObanRepo migration
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ObanRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ObanRepo

# Force ResultsRepo migration
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ResultsRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ResultsRepo
```

#### Production Environment
```bash
# Force ObanRepo migration
MIX_ENV=prod mix ecto.rollback --repo Uptrack.ObanRepo --step 1
MIX_ENV=prod mix ecto.migrate --repo Uptrack.ObanRepo

# Force ResultsRepo migration
MIX_ENV=prod mix ecto.rollback --repo Uptrack.ResultsRepo --step 1
MIX_ENV=prod mix ecto.migrate --repo Uptrack.ResultsRepo
```

### Expected Output

#### Successful ObanRepo Migration
```
[info] == Running 20250923102216 Uptrack.ObanRepo.Migrations.InitialSetup.up/0 forward
[info] execute "CREATE SCHEMA IF NOT EXISTS oban"
[info] create table if not exists oban.oban_jobs
[info] create index if not exists oban.oban_jobs_queue_index
...
[info] == Migrated 20250923102216 in 0.0s
```

#### Successful ResultsRepo Migration
```
[info] == Running 20250923102216 Uptrack.ResultsRepo.Migrations.InitialSetup.up/0 forward
[info] execute "CREATE SCHEMA IF NOT EXISTS results"
[info] create table results.monitor_results_free
[info] create table results.monitor_results_solo
[info] create table results.monitor_results_team
...
[info] == Migrated 20250923102216 in 0.0s
```

## Problem: TimescaleDB functions not available

### Symptoms
- Error: `function create_hypertable(unknown) does not exist`
- Error: `function add_retention_policy(unknown) does not exist`
- Migration fails with TimescaleDB-related errors

### Root Cause
TimescaleDB extension is not installed or not available in the database.

### Solution

#### Development (Optional TimescaleDB)
The migration is designed to handle missing TimescaleDB gracefully:
```elixir
try do
  execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE")
rescue
  _ -> :ok
end
```

#### Production (Required TimescaleDB)
Install TimescaleDB extension:
```sql
-- Connect as superuser
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
```

## Problem: Repo not started errors

### Symptoms
- Error: `could not lookup Ecto repo Uptrack.AppRepo because it was not started`
- Occurs when using `mix run` commands

### Root Cause
Repositories are not started in the Mix environment.

### Solution
Use proper Mix tasks instead of `mix run`:
```bash
# Instead of mix run commands, use:
mix ecto.migrate
mix ecto.rollback
mix ecto.create
mix ecto.drop
```

## Problem: Search path configuration errors

### Symptoms
- Tables created in wrong schema
- Cannot find tables in expected schema
- Search path warnings in logs

### Root Cause
Incorrect `search_path` configuration in database config.

### Solution
Update config files with proper parameter format:
```elixir
# OLD (deprecated)
config :uptrack, Uptrack.AppRepo,
  search_path: "app,public"

# NEW (correct)
config :uptrack, Uptrack.AppRepo,
  parameters: [search_path: "app,public"]
```

## Problem: Migration rollback failures

### Symptoms
- Error during rollback: `schema "oban" does not exist`
- Error: `function remove_retention_policy(unknown) does not exist`

### Root Cause
Attempting to rollback migrations that were never properly executed or trying to remove TimescaleDB policies that don't exist.

### Solution
The rollback is expected to show "schema does not exist" messages when schemas weren't created. This is normal behavior. Continue with the migrate command:

```bash
# Rollback may show errors (this is expected)
mix ecto.rollback --repo Uptrack.ObanRepo --step 1

# Then run migrate (this will work)
mix ecto.migrate --repo Uptrack.ObanRepo
```

## Problem: Connection pool exhaustion

### Symptoms
- Database connection timeouts
- Pool checkout timeout errors
- Slow application performance

### Root Cause
Insufficient connection pool sizes for the multi-repo architecture.

### Solution
Adjust pool sizes in config:
```elixir
# AppRepo - High read/write volume
config :uptrack, Uptrack.AppRepo,
  pool_size: 10

# ObanRepo - Advisory locks require smaller pool
config :uptrack, Uptrack.ObanRepo,
  pool_size: 5

# ResultsRepo - High volume time-series data
config :uptrack, Uptrack.ResultsRepo,
  pool_size: 10
```

## Verification Commands

### Check Migration Status
```bash
# Check individual repo status
MIX_ENV=dev mix ecto.migrations --repo Uptrack.AppRepo
MIX_ENV=dev mix ecto.migrations --repo Uptrack.ObanRepo
MIX_ENV=dev mix ecto.migrations --repo Uptrack.ResultsRepo
```

### Verify Schema Creation
```bash
# Check if all schemas exist
psql -d uptrack_dev -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('app', 'oban', 'results');"

# Should return:
# schema_name
# -----------
# app
# oban
# results
```

### Verify Table Creation
```sql
-- Check tables in each schema
\dt app.*
\dt oban.*
\dt results.*
```

## Recovery Procedures

### Complete Database Reset
```bash
# Nuclear option - destroys all data
MIX_ENV=dev mix ecto.drop
MIX_ENV=dev mix ecto.create
MIX_ENV=dev mix ecto.migrate
```

### Selective Schema Recreation
```bash
# Drop and recreate specific schemas
psql -d uptrack_dev -c "DROP SCHEMA IF EXISTS oban CASCADE;"
psql -d uptrack_dev -c "DROP SCHEMA IF EXISTS results CASCADE;"

# Then run forced migrations
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ObanRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ObanRepo
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ResultsRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ResultsRepo
```

## Prevention Best Practices

### 1. Always use repo-specific commands in CI/CD
```bash
# In deployment scripts
mix ecto.create
mix ecto.migrate  # This handles AppRepo
mix ecto.migrate --repo Uptrack.ObanRepo    # Force ObanRepo
mix ecto.migrate --repo Uptrack.ResultsRepo # Force ResultsRepo
```

### 2. Verify before declaring success
```bash
# Add verification step to deployment
psql -d $DATABASE_NAME -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('app', 'oban', 'results');" | grep -c "results\|oban\|app"
# Should return 3
```

### 3. Use health checks
```elixir
# In application health check
defmodule Uptrack.HealthCheck do
  def database_schemas_exist? do
    try do
      Uptrack.AppRepo.query!("SELECT 1 FROM app.users LIMIT 1")
      Uptrack.ObanRepo.query!("SELECT 1 FROM oban.oban_jobs LIMIT 1")
      Uptrack.ResultsRepo.query!("SELECT 1 FROM results.monitor_results_free LIMIT 1")
      true
    rescue
      _ -> false
    end
  end
end
```

## Emergency Contacts

If migration issues persist:
1. Check GitHub issues: https://github.com/anthropics/claude-code/issues
2. Review Ecto documentation for multi-repo setups
3. Consult TimescaleDB installation guides for production environments

## Related Documents

- [Database Deployment Specifications](./database-deployment-specifications.md)
- [Architecture Specifications](./architecture-specifications.md)
- [Implementation Plan](./implementation-plan.md)