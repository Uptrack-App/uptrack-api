# Integer Type Strategy Specification

## Overview

This document defines the integer type selection strategy for Uptrack's database columns, optimizing for monitoring application performance while maintaining data integrity. The strategy balances storage efficiency, query performance, and scale requirements specific to uptime monitoring workloads.

## Core Principles

### Performance First
- **Index efficiency**: Smaller integers mean more keys per index page
- **Join performance**: 4-byte integers are faster than 8-byte for frequent operations
- **Memory usage**: Reduced buffer pool consumption for high-volume queries
- **Network efficiency**: Less data transfer for monitoring results

### Scale-Appropriate Sizing
- **Monitor scale**: Support 100M+ monitors per account without overflow
- **Check frequency**: Handle billions of monitor checks per year
- **Metric precision**: Balance storage vs. accuracy for response times
- **Growth planning**: 10x safety margins for production scale

## Integer Type Selection Matrix

### BigInt (8 bytes) - Use For:
1. **High-volume primary keys**
   - `monitor_checks.id` - Billions of records expected
   - Time-series tables with rapid accumulation

2. **Foreign keys to high-volume tables**
   - `incidents.first_check_id` - References monitor_checks
   - `incidents.last_check_id` - References monitor_checks

3. **Account/tenant references**
   - `*.account_id` - Future multi-tenant scaling
   - Cross-schema references where volume is uncertain

### Int (4 bytes) - Use For:
1. **Business entity counts**
   - `monitors.interval` - 30-86400 seconds range
   - `monitors.timeout` - 1-300 seconds range
   - `alert_channels.display_order` - UI ordering

2. **Metric values with known bounds**
   - `monitor_checks.response_time` - 0-300000ms (5 minutes max)
   - `monitor_checks.status_code` - HTTP status codes (100-599)
   - `incidents.duration` - Incident length in seconds

3. **Configuration values**
   - `status_pages.display_order` - UI/API ordering
   - `regions.priority` - Failover priority (0-100)

### SmallInt (2 bytes) - Use For:
1. **Enumerated values**
   - Status indicators (up/down/unknown)
   - Alert states (pending/sent/failed)
   - Priority levels (1-5 scale)

2. **Small range counters**
   - Retry attempts (0-10)
   - Consecutive failures (0-100)

## Monitoring-Specific Considerations

### Response Time Storage
```elixir
# Store in milliseconds as Integer (not BigInt)
# Range: 0-300,000ms (5 minute timeout)
add :response_time, :integer  # 4 bytes sufficient
```

### Check Frequency Intervals
```elixir
# Store in seconds as Integer
# Range: 30 seconds - 24 hours (86,400 seconds)
add :interval, :integer  # 4 bytes sufficient
```

### Monitor Check IDs
```elixir
# High volume - use BigInt
# Expected: 1M+ checks per monitor per year
add :id, :bigserial, primary_key: true  # 8 bytes required
```

## Performance Impact Analysis

### Storage Efficiency
- **Int vs BigInt**: 50% storage reduction
- **Index size**: Proportional storage savings
- **Buffer pool**: More records fit in memory

### Query Performance
- **Range scans**: Faster on smaller keys
- **Aggregations**: Reduced CPU for SUM/AVG operations
- **Sorting**: Improved ORDER BY performance

### Network Transfer
- **API responses**: 50% reduction in numeric data transfer
- **Replication**: Faster replica synchronization
- **Backup/restore**: Reduced backup sizes

## Implementation Guidelines

### Schema Definition
```elixir
# Monitoring-optimized integer usage
defmodule Uptrack.Monitoring.MonitorCheck do
  schema "monitor_checks" do
    # High-volume primary key
    field :id, :integer, primary_key: true  # Auto-increment BigInt in DB

    # Foreign keys to high-volume tables
    field :monitor_id, Uniq.UUID  # References UUID table
    field :account_id, Uniq.UUID  # Tenant isolation

    # Bounded metric values
    field :response_time, :integer    # 0-300000ms
    field :status_code, :integer      # 100-599
    field :total_ms, :integer         # Total request time

    # Timestamp (managed by DB)
    field :checked_at, :utc_datetime
  end
end
```

### Migration Patterns
```elixir
# Create table with appropriate integer types
create table("results.monitor_checks") do
  add :id, :bigserial, primary_key: true
  add :monitor_id, :uuid, null: false
  add :account_id, :uuid, null: false
  add :response_time, :integer        # 4 bytes
  add :status_code, :integer          # 4 bytes
  add :total_ms, :integer             # 4 bytes
  add :checked_at, :utc_datetime, null: false
end
```

## Migration Strategy

### Phase 1: New Tables
- All new tables follow this specification
- Monitor check tables use optimized integer types
- Test performance improvements on new data

### Phase 2: High-Impact Optimizations
- Migrate metric columns in monitor_checks table
- Update response_time, status_code columns to integer
- Measure query performance improvements

### Phase 3: Complete Optimization
- Review remaining BigInt usage for optimization opportunities
- Update documentation and team guidelines
- Establish monitoring for integer overflow risks

## Overflow Protection

### Monitoring Safeguards
```elixir
# Add check constraints for critical bounds
create constraint("monitor_checks", "response_time_bounds",
  check: "response_time >= 0 AND response_time <= 300000")

create constraint("monitor_checks", "status_code_bounds",
  check: "status_code >= 100 AND status_code <= 599")
```

### Application Validation
```elixir
# Schema validations
defmodule MonitorCheck do
  def changeset(check, attrs) do
    check
    |> cast(attrs, [:response_time, :status_code])
    |> validate_number(:response_time, greater_than_or_equal_to: 0, less_than: 300_000)
    |> validate_number(:status_code, greater_than_or_equal_to: 100, less_than: 600)
  end
end
```

## Success Metrics

### Performance Targets
- **Query speed**: 25% improvement in aggregate queries
- **Index size**: 30% reduction in btree index storage
- **Memory usage**: 20% reduction in buffer pool consumption
- **Network transfer**: 15% reduction in API response sizes

### Reliability Measures
- **Zero overflow errors** in production
- **Consistent response times** under load
- **Successful data migrations** without downtime

---

*This specification optimizes integer usage for Uptrack's monitoring workloads while maintaining the scalability and reliability principles defined in the Constitution.*