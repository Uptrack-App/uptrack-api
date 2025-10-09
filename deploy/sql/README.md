# SQL Initialization Scripts

These scripts initialize the Postgres database for Uptrack's multi-repo architecture.

## Execution Order

Run these scripts in order on the **Patroni primary node** after the cluster is bootstrapped:

### 1. Initialize Schemas
```bash
psql -U postgres -d uptrack_prod -f 00-init-schemas.sql
```

**What it does:**
- Creates `app`, `oban`, and `results` schemas
- Creates `uptrack` user with appropriate permissions
- Sets up separate schema_migrations tables

**Important:** Change the default password `CHANGE_ME_IN_PRODUCTION` before running in production!

### 2. (Deprecated) TimescaleDB Setup

**NOTE:** Uptrack now uses **ClickHouse** for time-series data instead of TimescaleDB.

- ClickHouse is configured on Node C (see: `infra/nixos/services/clickhouse.nix`)
- Data is written via `Uptrack.ClickHouse.ResilientWriter`
- The `01-timescaledb-setup.sql` file is kept for reference only

### 3. Run Ecto Migrations
```bash
# From your app directory
/opt/uptrack/bin/uptrack eval "Uptrack.Release.migrate()"
```

**What it does:**
- Runs all pending migrations for AppRepo, ObanRepo, ResultsRepo
- Creates tables in their respective schemas
- Sets up Oban job tables

## Schema Overview

| Schema    | Purpose                          | Managed By      |
|-----------|----------------------------------|-----------------|
| `app`     | Core application data            | AppRepo         |
| `oban`    | Background job orchestration     | ObanRepo        |
| `results` | Time-series monitoring results   | ResultsRepo     |

## Verification

After running all scripts:

```bash
# Check schemas exist
psql -U uptrack -d uptrack_prod -c "\dn"

# Check TimescaleDB is enabled
psql -U uptrack -d uptrack_prod -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';"

# Check tables in each schema
psql -U uptrack -d uptrack_prod -c "\dt app.*"
psql -U uptrack -d uptrack_prod -c "\dt oban.*"
psql -U uptrack -d uptrack_prod -c "\dt results.*"
```

## Security Notes

1. **Change default password:** Edit `00-init-schemas.sql` and set a strong password
2. **Use environment variables:** In production, set `DATABASE_URL` with the correct credentials
3. **SSL connections:** Add `?ssl=true` to your production DATABASE_URL
4. **Firewall:** Only allow connections from Tailscale IPs (100.x.x.x)

## Troubleshooting

### "schema already exists"
Safe to ignore if re-running scripts. The `IF NOT EXISTS` clauses prevent errors.

### "permission denied"
Ensure you're running as the `postgres` superuser for initial setup.

### "extension timescaledb does not exist"
Install TimescaleDB package:
- Ubuntu: `apt install timescaledb-postgresql-16`
- NixOS: Add `postgresql.package.withPackages (ps: [ ps.timescaledb ])`
