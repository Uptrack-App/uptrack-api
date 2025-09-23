# TimescaleDB Setup for Uptrack

This document explains the TimescaleDB integration for handling high-volume monitor check data in the Uptrack monitoring application.

## Overview

Uptrack uses TimescaleDB to efficiently store and query time-series monitoring data. This setup supports:
- **50,000+ monitors** running checks every minute
- **~833 writes/second** sustained throughput
- **Automatic data compression** and retention policies
- **Pre-computed hourly statistics** for fast dashboard queries

## Architecture

### Database Schema

#### Primary Table: `monitor_checks_timeseries`
- **Type**: TimescaleDB Hypertable (automatically partitioned by time)
- **Purpose**: Stores all monitor check results
- **Capacity**: Handles 50k monitors × 1440 checks/day = 72M records/day

```sql
CREATE TABLE monitor_checks_timeseries (
  time TIMESTAMPTZ NOT NULL,              -- Partition key
  monitor_id INTEGER NOT NULL,            -- Foreign key to monitors
  response_time_ms INTEGER,               -- Response time in milliseconds
  status_code INTEGER,                    -- HTTP status code
  status VARCHAR NOT NULL,                -- 'up', 'down', 'timeout', 'error'
  error_message TEXT,                     -- Error details when applicable
  response_body TEXT,                     -- Truncated response for keyword monitoring
  check_id UUID NOT NULL PRIMARY KEY     -- Unique identifier for each check
);
```

#### Aggregated View: `monitor_stats_hourly`
- **Type**: TimescaleDB Continuous Aggregate (materialized view)
- **Purpose**: Pre-computed hourly statistics for fast dashboard queries
- **Updates**: Automatically refreshed every hour

```sql
CREATE MATERIALIZED VIEW monitor_stats_hourly AS
SELECT 
  time_bucket(INTERVAL '1 hour', time) AS bucket,
  monitor_id,
  COUNT(*) as total_checks,
  COUNT(CASE WHEN status = 'up' THEN 1 END) as up_checks,
  AVG(response_time_ms) as avg_response_time,
  MAX(response_time_ms) as max_response_time,
  MIN(response_time_ms) as min_response_time
FROM monitor_checks_timeseries
GROUP BY bucket, monitor_id;
```

### Performance Optimizations

#### Indexes
- `(monitor_id, time)` - Efficient time-range queries per monitor
- `(monitor_id, status)` - Fast status filtering
- `(time)` - Global time-based queries

#### Data Management Policies
- **Compression**: Data older than 7 days automatically compressed (~70% size reduction)
- **Retention**: Data older than 30 days automatically deleted
- **Aggregation**: Hourly stats computed and refreshed automatically

## Installation Requirements

### 1. TimescaleDB Installation

Choose one of the following options:

#### Option A: Docker (Recommended for Development)
```bash
docker run -d --name timescaledb -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=uptrack_dev \
  timescale/timescaledb:latest-pg15
```

#### Option B: macOS with Homebrew
```bash
brew tap timescale/tap
brew install timescaledb

# Add to postgresql.conf
echo "shared_preload_libraries = 'timescaledb'" >> /usr/local/var/postgres/postgresql.conf

# Restart PostgreSQL
brew services restart postgresql
```

#### Option C: Cloud Providers
- **Timescale Cloud**: Native TimescaleDB hosting
- **AWS RDS**: Supports TimescaleDB extension
- **Digital Ocean**: Managed PostgreSQL with TimescaleDB support

### 2. Database Migration

After TimescaleDB is installed:

```bash
# Run the migrations
mix ecto.migrate

# Verify setup
mix ecto.migrate --check
```

## Usage Examples

### Inserting Monitor Check Data

```elixir
# Single insert
%{
  time: DateTime.utc_now(),
  monitor_id: 123,
  response_time_ms: 245,
  status_code: 200,
  status: "up",
  check_id: Ecto.UUID.generate()
}
|> Uptrack.Repo.insert_into("monitor_checks_timeseries")

# Batch insert (recommended for performance)
checks = [
  %{time: DateTime.utc_now(), monitor_id: 1, response_time_ms: 200, status: "up", check_id: Ecto.UUID.generate()},
  %{time: DateTime.utc_now(), monitor_id: 2, response_time_ms: 150, status: "up", check_id: Ecto.UUID.generate()},
  # ... up to 500 records per batch
]

Uptrack.Repo.insert_all("monitor_checks_timeseries", checks)
```

### Querying Monitor Data

```elixir
# Recent checks for a monitor
query = from(c in "monitor_checks_timeseries",
  where: c.monitor_id == ^monitor_id and 
         c.time >= ago(1, "day"),
  order_by: [desc: c.time],
  limit: 100
)

# Uptime percentage for last 24 hours
uptime_query = from(c in "monitor_checks_timeseries",
  where: c.monitor_id == ^monitor_id and 
         c.time >= ago(1, "day"),
  select: %{
    total: count(),
    up: count(c.status == "up")
  }
)

# Hourly stats (uses pre-computed aggregate)
stats_query = from(s in "monitor_stats_hourly",
  where: s.monitor_id == ^monitor_id and
         s.bucket >= ago(7, "day"),
  select: %{
    time: s.bucket,
    uptime_pct: s.up_checks / s.total_checks * 100,
    avg_response: s.avg_response_time
  }
)
```

## Scaling Considerations

### For 20,000 Monitors
- **Write load**: ~333 writes/second
- **Storage**: ~17GB for 30 days
- **Server**: $15 PostgreSQL instance sufficient

### For 50,000 Monitors  
- **Write load**: ~833 writes/second
- **Storage**: ~42GB for 30 days
- **Server**: $25-50 PostgreSQL instance recommended

### For 100,000+ Monitors
- **Write load**: 1,667+ writes/second
- **Storage**: 84GB+ for 30 days
- **Architecture**: Consider read replicas, connection pooling, distributed workers

## Monitoring & Maintenance

### Key Metrics to Monitor
```sql
-- Check hypertable stats
SELECT * FROM timescaledb_information.hypertables 
WHERE hypertable_name = 'monitor_checks_timeseries';

-- Compression ratios
SELECT * FROM timescaledb_information.compression_settings 
WHERE hypertable_name = 'monitor_checks_timeseries';

-- Chunk information
SELECT * FROM timescaledb_information.chunks 
WHERE hypertable_name = 'monitor_checks_timeseries'
ORDER BY range_start DESC LIMIT 10;
```

### Maintenance Commands
```sql
-- Manual compression (usually automatic)
SELECT compress_chunk(chunk_name) FROM timescaledb_information.chunks 
WHERE hypertable_name = 'monitor_checks_timeseries' AND NOT is_compressed;

-- Refresh continuous aggregate manually
CALL refresh_continuous_aggregate('monitor_stats_hourly', NULL, NULL);

-- Check policy status
SELECT * FROM timescaledb_information.jobs;
```

## Cost Analysis

### Storage Costs (30-day retention)
- **Raw data**: ~50 bytes per check
- **20k monitors**: 20k × 1440 × 30 × 50 bytes = ~42GB
- **50k monitors**: 50k × 1440 × 30 × 50 bytes = ~105GB
- **With compression**: ~30-40% of raw size after 7 days

### Hosting Options
1. **$15 PostgreSQL**: Good for 20k monitors
2. **$25-50 PostgreSQL**: Suitable for 50k monitors  
3. **Dedicated TimescaleDB**: $100+ for 100k+ monitors

## Troubleshooting

### Common Issues

#### Extension Not Found
```
ERROR: extension "timescaledb" is not available
```
**Solution**: Install TimescaleDB on PostgreSQL host first

#### Hypertable Creation Fails
```
ERROR: function create_hypertable does not exist
```
**Solution**: Ensure TimescaleDB extension is enabled: `CREATE EXTENSION timescaledb;`

#### High Memory Usage
**Symptoms**: Out of memory errors during high write loads
**Solution**: 
- Increase PostgreSQL `shared_buffers`
- Use batch inserts (500+ records per batch)
- Consider connection pooling

#### Slow Queries
**Symptoms**: Dashboard queries taking >1 second
**Solution**:
- Use hourly aggregates instead of raw data for charts
- Add appropriate indexes
- Consider read replicas for reporting queries

## Migration Files

The TimescaleDB setup consists of three migration files:

1. **`enable_timescaledb.exs`** - Installs the extension
2. **`create_monitor_checks_hypertable.exs`** - Creates the main table and converts to hypertable
3. **`setup_timescale_policies.exs`** - Sets up retention, compression, and aggregation policies

All migrations are reversible and can be rolled back if needed.