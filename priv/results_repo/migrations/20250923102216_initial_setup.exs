defmodule Uptrack.ResultsRepo.Migrations.InitialSetup do
  use Ecto.Migration

  def up do
    # Create results schema
    execute("CREATE SCHEMA IF NOT EXISTS results")

    # Try to enable TimescaleDB extension (skip if not available)
    try do
      execute("CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE")
    rescue
      _ -> :ok
    end

    # Create tier-based hypertables for monitor results
    create table("results.monitor_results_free", primary_key: false) do
      add :ts, :utc_datetime_usec, null: false
      add :monitor_id, :bigint, null: false
      add :account_id, :bigint, null: false
      add :ok, :boolean, null: false
      add :status_code, :integer
      add :err_kind, :text
      add :total_ms, :integer
      add :probe_region, :text, default: "primary"
    end

    create table("results.monitor_results_solo", primary_key: false) do
      add :ts, :utc_datetime_usec, null: false
      add :monitor_id, :bigint, null: false
      add :account_id, :bigint, null: false
      add :ok, :boolean, null: false
      add :status_code, :integer
      add :err_kind, :text
      add :total_ms, :integer
      add :probe_region, :text, default: "primary"
    end

    create table("results.monitor_results_team", primary_key: false) do
      add :ts, :utc_datetime_usec, null: false
      add :monitor_id, :bigint, null: false
      add :account_id, :bigint, null: false
      add :ok, :boolean, null: false
      add :status_code, :integer
      add :err_kind, :text
      add :total_ms, :integer
      add :probe_region, :text, default: "primary"
    end

    # Add primary keys for hypertables
    execute("ALTER TABLE results.monitor_results_free ADD PRIMARY KEY (monitor_id, ts)")
    execute("ALTER TABLE results.monitor_results_solo ADD PRIMARY KEY (monitor_id, ts)")
    execute("ALTER TABLE results.monitor_results_team ADD PRIMARY KEY (monitor_id, ts)")

    # Convert to hypertables (only if TimescaleDB is available)
    try do
      execute("SELECT create_hypertable('results.monitor_results_free', 'ts', chunk_time_interval => interval '1 day', if_not_exists => TRUE)")
      execute("SELECT create_hypertable('results.monitor_results_solo', 'ts', chunk_time_interval => interval '1 day', if_not_exists => TRUE)")
      execute("SELECT create_hypertable('results.monitor_results_team', 'ts', chunk_time_interval => interval '1 day', if_not_exists => TRUE)")
    rescue
      _ -> :ok
    end

    # Create indexes for efficient queries
    create index("results.monitor_results_free", [:account_id, :ts])
    create index("results.monitor_results_solo", [:account_id, :ts])
    create index("results.monitor_results_team", [:account_id, :ts])

    # Create unified view for reading across all tiers
    execute("""
    CREATE OR REPLACE VIEW results.monitor_results AS
    SELECT * FROM results.monitor_results_free
    UNION ALL
    SELECT * FROM results.monitor_results_solo
    UNION ALL
    SELECT * FROM results.monitor_results_team
    """)

    # Create TimescaleDB continuous aggregates and policies (only if TimescaleDB is available)
    try do
      # Create 1-minute rollup continuous aggregate
      execute("""
      CREATE MATERIALIZED VIEW results.mr_1m
      WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 minute', ts) AS bucket,
             account_id, monitor_id,
             count(*) AS checks,
             sum((ok)::int) AS ok_count,
             avg(total_ms) AS avg_ms,
             percentile_cont(0.95) WITHIN GROUP (ORDER BY total_ms) AS p95_ms
      FROM results.monitor_results
      GROUP BY bucket, account_id, monitor_id
      WITH NO DATA
      """)

      # Create 5-minute rollup continuous aggregate
      execute("""
      CREATE MATERIALIZED VIEW results.mr_5m
      WITH (timescaledb.continuous) AS
      SELECT time_bucket('5 minutes', ts) AS bucket,
             account_id, monitor_id,
             count(*) AS checks,
             sum((ok)::int) AS ok_count,
             avg(total_ms) AS avg_ms,
             percentile_cont(0.95) WITHIN GROUP (ORDER BY total_ms) AS p95_ms
      FROM results.monitor_results
      GROUP BY bucket, account_id, monitor_id
      WITH NO DATA
      """)

      # Create daily rollup continuous aggregate
      execute("""
      CREATE MATERIALIZED VIEW results.mr_daily
      WITH (timescaledb.continuous) AS
      SELECT time_bucket('1 day', ts) AS bucket,
             account_id, monitor_id,
             count(*) AS checks,
             sum((ok)::int) AS ok_count,
             avg(total_ms) AS avg_ms,
             percentile_cont(0.95) WITHIN GROUP (ORDER BY total_ms) AS p95_ms,
             (sum((ok)::int)::float / count(*) * 100) AS uptime_percentage
      FROM results.monitor_results
      GROUP BY bucket, account_id, monitor_id
      WITH NO DATA
      """)

      # Add continuous aggregate policies
      execute("""
      SELECT add_continuous_aggregate_policy('results.mr_1m',
        start_offset => INTERVAL '3 days',
        end_offset => INTERVAL '1 minute',
        schedule_interval => INTERVAL '1 minute')
      """)

      execute("""
      SELECT add_continuous_aggregate_policy('results.mr_5m',
        start_offset => INTERVAL '90 days',
        end_offset => INTERVAL '5 minutes',
        schedule_interval => INTERVAL '5 minutes')
      """)

      execute("""
      SELECT add_continuous_aggregate_policy('results.mr_daily',
        start_offset => INTERVAL '2 years',
        end_offset => INTERVAL '1 day',
        schedule_interval => INTERVAL '1 hour')
      """)

      # Add compression settings
      execute("ALTER TABLE results.monitor_results_free SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id')")
      execute("ALTER TABLE results.monitor_results_solo SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id')")
      execute("ALTER TABLE results.monitor_results_team SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id')")

      # Add compression policies
      execute("SELECT add_compression_policy('results.monitor_results_free', INTERVAL '7 days')")
      execute("SELECT add_compression_policy('results.monitor_results_solo', INTERVAL '7 days')")
      execute("SELECT add_compression_policy('results.monitor_results_team', INTERVAL '7 days')")

      # Add retention policies based on user tiers
      execute("SELECT add_retention_policy('results.monitor_results_free', INTERVAL '120 days')")
      execute("SELECT add_retention_policy('results.monitor_results_solo', INTERVAL '455 days')")
      execute("SELECT add_retention_policy('results.monitor_results_team', INTERVAL '455 days')")
    rescue
      _ -> :ok
    end
  end

  def down do
    # Remove TimescaleDB policies first (only if TimescaleDB is available)
    try do
      execute("SELECT remove_retention_policy('results.monitor_results_free')")
      execute("SELECT remove_retention_policy('results.monitor_results_solo')")
      execute("SELECT remove_retention_policy('results.monitor_results_team')")

      execute("SELECT remove_compression_policy('results.monitor_results_free')")
      execute("SELECT remove_compression_policy('results.monitor_results_solo')")
      execute("SELECT remove_compression_policy('results.monitor_results_team')")

      execute("SELECT remove_continuous_aggregate_policy('results.mr_1m')")
      execute("SELECT remove_continuous_aggregate_policy('results.mr_5m')")
      execute("SELECT remove_continuous_aggregate_policy('results.mr_daily')")
    rescue
      _ -> :ok
    end

    # Drop materialized views
    execute("DROP MATERIALIZED VIEW IF EXISTS results.mr_daily")
    execute("DROP MATERIALIZED VIEW IF EXISTS results.mr_5m")
    execute("DROP MATERIALIZED VIEW IF EXISTS results.mr_1m")

    # Drop view and tables
    execute("DROP VIEW IF EXISTS results.monitor_results")
    drop table("results.monitor_results_free")
    drop table("results.monitor_results_solo")
    drop table("results.monitor_results_team")

    execute("DROP SCHEMA IF EXISTS results CASCADE")
  end
end