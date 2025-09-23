# Results Schema Migration (results schema with TimescaleDB)

```sql
-- Enable TimescaleDB extension (database level, not per schema)
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create results schema
CREATE SCHEMA IF NOT EXISTS results;

-- Paid hypertable
CREATE TABLE results.monitor_results_paid (
    ts timestamptz NOT NULL,
    monitor_id bigint NOT NULL,
    account_id bigint NOT NULL,
    ok boolean NOT NULL,
    status_code int,
    err_kind text,
    total_ms int,
    bytes int,
    probe_region text
);
SELECT create_hypertable('results.monitor_results_paid','ts',
  chunk_time_interval => interval '1 day',
  if_not_exists => TRUE);

-- Free hypertable
CREATE TABLE results.monitor_results_free (LIKE results.monitor_results_paid INCLUDING ALL);
SELECT create_hypertable('results.monitor_results_free','ts',
  chunk_time_interval => interval '1 day',
  if_not_exists => TRUE);

-- Convenience view
CREATE OR REPLACE VIEW results.monitor_results AS
SELECT * FROM results.monitor_results_paid
UNION ALL
SELECT * FROM results.monitor_results_free;

-- Indexes
CREATE INDEX idx_results_paid_monitor_ts ON results.monitor_results_paid(monitor_id, ts DESC);
CREATE INDEX idx_results_free_monitor_ts ON results.monitor_results_free(monitor_id, ts DESC);

-- Continuous aggregate example (1 minute)
CREATE MATERIALIZED VIEW results.mr_1m
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 minute', ts) AS bucket,
       account_id, monitor_id,
       count(*) AS checks,
       sum((ok)::int) AS ok_count,
       avg(total_ms) AS avg_ms,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY total_ms) AS p95_ms
FROM results.monitor_results
GROUP BY bucket, account_id, monitor_id;

-- Continuous aggregate policy
SELECT add_continuous_aggregate_policy('results.mr_1m',
  start_offset => INTERVAL '3 days',
  end_offset => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

-- Compression policies
ALTER TABLE results.monitor_results_paid
  SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id');
ALTER TABLE results.monitor_results_free
  SET (timescaledb.compress, timescaledb.compress_segmentby = 'monitor_id');
SELECT add_compression_policy('results.monitor_results_paid', INTERVAL '7 days');
SELECT add_compression_policy('results.monitor_results_free', INTERVAL '7 days');

-- Retention
SELECT add_retention_policy('results.monitor_results_paid', INTERVAL '365 days');
SELECT add_retention_policy('results.monitor_results_free', INTERVAL '180 days');
```
