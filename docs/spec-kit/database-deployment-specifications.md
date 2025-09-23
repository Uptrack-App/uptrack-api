# Database Deployment Specifications

## Overview

This document specifies the multi-repo database architecture deployment procedures for Uptrack's scalable monitoring system.

## Architecture Components

### Repository Structure
- **AppRepo**: Application data (users, monitors, incidents, alerts, status pages)
- **ObanRepo**: Background job processing system
- **ResultsRepo**: Time-series monitoring data with TimescaleDB support

### Schema Organization
```
uptrack_dev/uptrack_prod database:
├── app schema           # Application data
├── oban schema          # Job processing
└── results schema       # Time-series monitoring data
```

## Migration Commands

### Development Environment

#### Initial Setup
```bash
# Create database and run all migrations
MIX_ENV=dev mix ecto.drop
MIX_ENV=dev mix ecto.create
MIX_ENV=dev mix ecto.migrate
```

#### Force Migration Re-run (if schemas missing)
```bash
# ObanRepo migration
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ObanRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ObanRepo

# ResultsRepo migration
MIX_ENV=dev mix ecto.rollback --repo Uptrack.ResultsRepo --step 1
MIX_ENV=dev mix ecto.migrate --repo Uptrack.ResultsRepo
```

### Production Environment

#### Initial Deployment
```bash
# Create database and run all migrations
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate
```

#### Schema Recovery (if migrations show "already up" but schemas missing)
```bash
# Force ObanRepo migration
MIX_ENV=prod mix ecto.rollback --repo Uptrack.ObanRepo --step 1
MIX_ENV=prod mix ecto.migrate --repo Uptrack.ObanRepo

# Force ResultsRepo migration
MIX_ENV=prod mix ecto.rollback --repo Uptrack.ResultsRepo --step 1
MIX_ENV=prod mix ecto.migrate --repo Uptrack.ResultsRepo
```

## Migration Troubleshooting

### Shared Migration Status Issue

**Problem**: All repos share the same `schema_migrations` table, causing migrations to appear "up" even when schemas weren't created.

**Solution**: Use repo-specific rollback and migrate commands to force execution.

### TimescaleDB Dependencies

**Development**: TimescaleDB functions are wrapped in try-catch blocks for optional availability.

**Production**: Ensure TimescaleDB extension is available:
```sql
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;
```

## Manual Schema Creation

If automation fails, create schemas manually:

### Using psql
```bash
psql -d uptrack_dev -c "CREATE SCHEMA IF NOT EXISTS oban; CREATE SCHEMA IF NOT EXISTS results;"
```

### Using PostgreSQL CLI
```sql
\c uptrack_dev
CREATE SCHEMA IF NOT EXISTS oban;
CREATE SCHEMA IF NOT EXISTS results;
\q
```

## Database Configuration

### Repository Configs (config/dev.exs)
```elixir
# AppRepo - Application data
config :uptrack, Uptrack.AppRepo,
  parameters: [search_path: "app,public"]

# ObanRepo - Job processing
config :uptrack, Uptrack.ObanRepo,
  parameters: [search_path: "oban,public"]

# ResultsRepo - Time-series data
config :uptrack, Uptrack.ResultsRepo,
  parameters: [search_path: "results,public"]
```

## Migration Files

### Created Migrations
- `priv/app_repo/migrations/20250923102216_initial_setup.exs`
- `priv/oban_repo/migrations/20250923102216_initial_setup.exs`
- `priv/results_repo/migrations/20250923102216_initial_setup.exs`

### Migration Features

#### AppRepo Tables
- users, monitors, incidents, incident_updates
- alert_channels, status_pages, status_page_monitors
- monitor_checks (metadata only)

#### ObanRepo Tables
- Complete Oban v2.20+ job processing system
- oban_jobs, oban_peers with proper indexing

#### ResultsRepo Tables
- Tier-based hypertables: monitor_results_{free,solo,team}
- TimescaleDB continuous aggregates: mr_1m, mr_5m, mr_daily
- Unified view: monitor_results
- Compression and retention policies

## Verification Commands

### Check Schema Existence
```bash
# Using mix
MIX_ENV=dev mix ecto.migrations --repo Uptrack.AppRepo
MIX_ENV=dev mix ecto.migrations --repo Uptrack.ObanRepo
MIX_ENV=dev mix ecto.migrations --repo Uptrack.ResultsRepo

# Using psql
psql -d uptrack_dev -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('app', 'oban', 'results');"
```

### Check Table Creation
```sql
-- App schema tables
\dt app.*

-- Oban schema tables
\dt oban.*

-- Results schema tables
\dt results.*
```

## Deployment Checklist

### Pre-deployment
- [ ] Database server accessible
- [ ] PostgreSQL 12+ available
- [ ] TimescaleDB extension available (for production)
- [ ] Database credentials configured

### Deployment Steps
1. [ ] Run `mix ecto.create`
2. [ ] Run `mix ecto.migrate`
3. [ ] Verify all three schemas exist
4. [ ] If schemas missing, run force migration commands
5. [ ] Verify table creation in each schema
6. [ ] Test application connectivity to all repos

### Post-deployment Verification
- [ ] Application starts without repo errors
- [ ] Background jobs can be queued (ObanRepo)
- [ ] Monitoring data can be stored (ResultsRepo)
- [ ] User authentication works (AppRepo)

## Common Issues

### "Migrations already up" but schemas missing
**Cause**: Shared migration status table across repos
**Fix**: Use repo-specific rollback and migrate commands

### TimescaleDB functions not available
**Cause**: Extension not installed
**Fix**: Install TimescaleDB or use development fallbacks

### Connection errors to specific repos
**Cause**: Search path configuration
**Fix**: Verify `parameters: [search_path: "schema,public"]` in config

## Performance Considerations

### Connection Pooling
- AppRepo: 10 connections (high read/write)
- ObanRepo: 5 connections (advisory locks require lower pool)
- ResultsRepo: 10 connections (high volume time-series data)

### Index Strategy
- AppRepo: User-based queries, monitor relationships
- ObanRepo: Job state, queue, priority, scheduling
- ResultsRepo: Time-based queries, monitor_id, account_id

### Data Retention
- Free tier: 120 days
- Solo/Team tiers: 455 days (15 months)
- Compression after 7 days
- Continuous aggregates for efficient queries

## Related Files

- `lib/uptrack/app_repo.ex` - Application repository
- `lib/uptrack/oban_repo.ex` - Job processing repository
- `lib/uptrack/results_repo.ex` - Time-series repository
- `config/dev.exs` - Development database configuration
- `config/prod.exs` - Production database configuration
- `scripts/setup_db.exs` - Manual schema creation script