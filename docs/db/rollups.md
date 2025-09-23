# TimescaleDB Rollups in Uptrack

## What are Rollups?

Rollups are **pre-calculated aggregations** of time-series data that summarize raw monitoring check results into different time granularities. Instead of storing and querying millions of individual data points, rollups provide efficient summaries for dashboards and analytics.

## Why Use Rollups?

1. **Performance**: Querying 365 daily summaries is much faster than millions of raw checks
2. **Storage efficiency**: Reduces data volume while preserving key metrics
3. **Cost optimization**: Less storage and compute resources needed for historical queries
4. **User experience**: Dashboards load faster with pre-aggregated data

## Rollup Strategy in Uptrack

We implement a **three-tier rollup hierarchy**:

### 1. Raw Data (Hypertables)
- `monitor_results_paid` → 365d retention, compress after 7d
- `monitor_results_free` → 180d retention, compress after 7d
- Individual check results stored at full granularity

### 2. 1-Minute Rollups
- **Purpose**: Medium-term detailed analysis
- **Window**: 3–14 day queries
- **Aggregations**: avg, min, max response times per minute
- **Use case**: Recent performance trends, incident analysis

### 3. 5-Minute Rollups
- **Purpose**: Longer-term trend analysis
- **Window**: 90–180 day queries
- **Aggregations**: avg, min, max response times per 5-minute bucket
- **Use case**: Weekly/monthly performance reports

### 4. Daily Rollups
- **Purpose**: Historical trends and capacity planning
- **Window**: Up to 2 years
- **Aggregations**: avg, min, max, uptime percentage per day
- **Use case**: Annual reports, long-term trend analysis

## Query Strategy

**Rule**: Dashboards always query rollups, never raw hypertables directly.

```sql
-- ❌ Don't query raw data for historical views
SELECT * FROM monitor_results_paid WHERE created_at > NOW() - INTERVAL '30 days';

-- ✅ Query appropriate rollup tier
SELECT * FROM monitor_results_daily_rollup WHERE day > NOW() - INTERVAL '30 days';
```

## Data Flow

```
Raw Checks (every 30s)
    ↓
1-min Continuous Aggregates
    ↓
5-min Continuous Aggregates
    ↓
Daily Continuous Aggregates
    ↓
Dashboard Queries
```

## Implementation Notes

- **Continuous Aggregates**: TimescaleDB automatically maintains rollups as new data arrives
- **Retention Policies**: Raw data expires, but rollups are kept longer
- **Compression**: Older data is compressed to reduce storage costs
- **Schema Separation**: Rollups live in the `results` schema alongside raw hypertables

## Benefits for Scaling

- **100 users**: Raw data queries acceptable
- **1,000+ users**: Rollups become essential for performance
- **Cost predictable**: Storage grows linearly with rollup strategy, not exponentially with raw data