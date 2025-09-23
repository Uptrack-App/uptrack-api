# Architecture Specifications

*Executable specifications for Uptrack's infrastructure and scaling strategy*

## Database Architecture Specification

### Multi-Repository Pattern
```yaml
spec_id: multi_repo_architecture
capability: Isolated database concerns for scalability
requirements:
  - Three dedicated Ecto repositories
  - Schema-based separation within single database initially
  - Painless migration to separate databases via environment variables
  - Connection pooling per repository

repositories:
  app_repo:
    schema: "app"
    purpose: "User accounts, monitors, incidents, billing"
    pool_size: 10
    search_path: ["app", "public"]

  oban_repo:
    schema: "oban"
    purpose: "Background job orchestration"
    pool_size: 5
    search_path: ["oban", "public"]
    connection_mode: "SESSION" # Required for advisory locks

  results_repo:
    schema: "results"
    purpose: "Time-series monitoring data and rollups"
    pool_size: 10
    search_path: ["results", "public"]

migration_strategy:
  phase_1: "All repos → same database, different schemas"
  phase_2: "AppRepo + ObanRepo → HA Postgres cluster"
  phase_3: "ResultsRepo → dedicated TimescaleDB cluster"

configuration:
  env_variables:
    - APP_DATABASE_URL
    - OBAN_DATABASE_URL
    - RESULTS_DATABASE_URL
  initial_setup: "All URLs point to same database"
  migration: "Change URLs, restart application"
```

### TimescaleDB Integration
```yaml
spec_id: timescaledb_hypertables
capability: Efficient time-series data storage
requirements:
  - Hypertables partitioned by user tier
  - Automatic compression after 7 days
  - Tier-based retention policies
  - Continuous aggregates for dashboard performance

hypertables:
  monitor_results_free:
    retention: "120 days"
    target_users: "Free tier"
    compression: "7 days"

  monitor_results_solo:
    retention: "455 days"
    target_users: "Solo tier"
    compression: "7 days"

  monitor_results_team:
    retention: "455 days"
    target_users: "Team tier"
    compression: "7 days"

partitioning:
  strategy: "time-based"
  chunk_interval: "1 day"
  partition_key: "ts" # timestamp column

indexing:
  primary: "(monitor_id, ts)"
  secondary:
    - "(account_id, ts)"
    - "(ts)" # For time-range queries
```

### Rollup Strategy
```yaml
spec_id: continuous_aggregates
capability: Pre-computed analytics for dashboard performance
requirements:
  - Three-tier rollup hierarchy
  - Automatic policy management
  - Dashboard queries NEVER hit raw data
  - Configurable aggregation windows

rollup_tiers:
  one_minute:
    materialized_view: "results.mr_1m"
    source: "results.monitor_results" # Union view
    window: "1 minute"
    retention_policy: "3-14 day queries"
    refresh_policy: "1 minute"
    metrics:
      - count(*) as checks
      - sum((ok)::int) as ok_count
      - avg(total_ms) as avg_ms
      - percentile_cont(0.95) within group (order by total_ms) as p95_ms

  five_minute:
    materialized_view: "results.mr_5m"
    source: "results.monitor_results"
    window: "5 minutes"
    retention_policy: "90-180 day queries"
    refresh_policy: "5 minutes"
    metrics: # Same as one_minute

  daily:
    materialized_view: "results.mr_daily"
    source: "results.monitor_results"
    window: "1 day"
    retention_policy: "Up to 2 years"
    refresh_policy: "1 hour"
    metrics:
      - count(*) as checks
      - sum((ok)::int) as ok_count
      - avg(total_ms) as avg_ms
      - percentile_cont(0.95) within group (order by total_ms) as p95_ms
      - (sum((ok)::int)::float / count(*) * 100) as uptime_percentage

query_routing:
  dashboard_24h: "query mr_1m rollups"
  dashboard_7d: "query mr_5m rollups"
  dashboard_30d_plus: "query mr_daily rollups"
  rule: "NEVER query raw hypertables for analytics"
```

## Job Processing Specification

### Oban Configuration
```yaml
spec_id: oban_job_system
capability: Reliable background job processing
requirements:
  - Dedicated ObanRepo with SESSION pooling
  - Queue-based job separation
  - Automatic pruning of completed jobs
  - Cron-based scheduling
  - Author-recommended optimizations

configuration:
  repo: "Uptrack.ObanRepo"
  plugins:
    - name: "Oban.Plugins.Pruner"
      config: {max_age: 300} # 5 minutes
    - name: "Oban.Plugins.Cron"
      config:
        crontab:
          - schedule: "*/30 * * * * *" # Every 30 seconds
            worker: "Uptrack.Monitoring.SchedulerWorker"

queues:
  default: 10 # General purpose jobs
  monitor_checks: 25 # Monitor execution (high concurrency)
  alerts: 5 # Notification delivery

worker_design:
  scheduler_worker:
    purpose: "Identify monitors due for checking"
    frequency: "Every 30 seconds via cron"
    behavior: "Enqueue CheckWorker jobs for due monitors"

  check_worker:
    purpose: "Execute individual monitor checks"
    queue: "monitor_checks"
    concurrency: 25
    max_attempts: 3
    behavior: "Perform check, store result, handle incidents"

optimization_principles:
  - minimize_job_args: "Store only monitor_id, not full monitor object"
  - prune_aggressively: "Delete completed jobs after 5 minutes"
  - isolate_from_app: "Separate connection pool prevents contention"
  - use_insert_all: "Batch job creation when possible"
```

### Monitoring Scheduler
```yaml
spec_id: monitor_scheduler
capability: Intelligent check scheduling
requirements:
  - Respect individual monitor intervals
  - Prevent duplicate checks for same monitor
  - Handle monitor state changes (active/paused)
  - Distribute load evenly across time

scheduling_logic:
  trigger: "SchedulerWorker runs every 30 seconds"
  evaluation: "Check each active monitor's last check time"
  condition: "current_time - last_check_time >= monitor.interval"
  action: "Enqueue ObanCheckWorker job for monitor"

load_distribution:
  jitter: "±5 seconds on check scheduling"
  prevention: "Skip if previous check still in progress"
  backpressure: "Queue monitoring to prevent overload"

state_handling:
  active_monitors: "Include in scheduling evaluation"
  paused_monitors: "Skip entirely"
  deleted_monitors: "Remove from scheduling"
  new_monitors: "Include immediately"
```

## High Availability Specification

### Infrastructure Scaling Path
```yaml
spec_id: ha_migration_path
capability: Zero-downtime scaling to high availability
requirements:
  - Phase-based migration approach
  - Environment variable configuration only
  - No application code changes required
  - Documented rollback procedures

phase_1_current:
  cost: "~$50/month"
  architecture:
    - "2x CPX11 app nodes + Hetzner Load Balancer"
    - "1x CPX21 database (Postgres + TimescaleDB)"
    - "All schemas in single database"
  availability: "App tier HA, database SPOF"
  rto: "10-15 minutes (backup restore)"

phase_2_database_ha:
  cost: "~$90-130/month"
  migration_steps:
    - "Deploy HA Postgres cluster (Patroni or Managed PG)"
    - "Update APP_DATABASE_URL and OBAN_DATABASE_URL"
    - "Restart application nodes"
  architecture:
    - "App + Oban → HA Postgres cluster"
    - "Results → same database (temporary)"
  availability: "Full HA for app data"

phase_3_results_scale:
  cost: "~$150-200/month"
  migration_steps:
    - "Deploy dedicated TimescaleDB cluster"
    - "Update RESULTS_DATABASE_URL"
    - "Restart application nodes"
  architecture:
    - "App + Oban → HA Postgres cluster"
    - "Results → dedicated TimescaleDB cluster"
  availability: "Full separation and scaling"

guardrails:
  - "Always use 3 separate repo modules"
  - "Environment variables control all database connections"
  - "No schema mixing between repositories"
  - "Migrations are idempotent and reversible"
```

### Backup and Recovery
```yaml
spec_id: backup_recovery
capability: Data protection and disaster recovery
requirements:
  - Automated backups for all data
  - Point-in-time recovery capability
  - Cross-region backup storage
  - Documented recovery procedures

backup_strategy:
  frequency: "Continuous WAL archiving + nightly base backups"
  retention: "30 days point-in-time recovery"
  storage: "Hetzner Storage Box (encrypted)"
  verification: "Monthly restore tests"

recovery_procedures:
  rto_target: "15 minutes"
  rpo_target: "5 minutes" # Maximum data loss
  automation: "Scripted recovery procedures"
  testing: "Quarterly disaster recovery drills"

monitoring:
  backup_alerts: "Failed backup notifications"
  storage_monitoring: "Backup storage usage tracking"
  recovery_testing: "Automated recovery validation"
```

## Performance Specification

### Response Time Targets
```yaml
spec_id: performance_targets
capability: Measurable performance commitments
requirements:
  - Dashboard load times under 2 seconds
  - API response times under 500ms
  - Monitor check intervals respected within 5%
  - Alert delivery under 30 seconds

benchmarks:
  dashboard_30_day: "< 2 seconds to load charts"
  dashboard_realtime: "< 100ms status updates"
  api_monitor_list: "< 500ms for 100 monitors"
  api_incident_list: "< 500ms for 30 days"
  monitor_check_jitter: "< 5% deviation from configured interval"
  alert_latency: "< 30 seconds from incident to notification"

monitoring:
  telemetry: "Track all response times"
  alerting: "Performance regression alerts"
  trending: "Weekly performance reports"
```

### Capacity Planning
```yaml
spec_id: capacity_limits
capability: Defined scaling boundaries
requirements:
  - Support 100 free + 500 paid users on single node
  - Handle 1000+ monitors without degradation
  - Predictable storage growth with compression
  - Linear cost scaling with user growth

current_limits:
  concurrent_checks: "25 (Oban queue limit)"
  monitors_per_user: "Unlimited (plan-based)"
  check_frequency: "30 seconds minimum"
  data_retention: "Tier-based (120d to 455d)"

scaling_indicators:
  cpu_utilization: "> 70% sustained"
  memory_usage: "> 80% of available"
  disk_io: "> 80% utilization"
  queue_depth: "> 100 pending jobs

autoscaling_triggers:
  horizontal_app: "Add app nodes when CPU > 70%"
  vertical_db: "Increase database resources when memory > 80%"
  storage: "Add storage when usage > 85%"
```

---

*These architectural specifications ensure Uptrack scales reliably from single-node deployment to enterprise-grade high availability.*