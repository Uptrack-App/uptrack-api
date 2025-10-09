-- 01-timescaledb-setup.sql
-- NOTE: This file is deprecated - Uptrack now uses ClickHouse for time-series data
--
-- Time-series monitor check results are stored in ClickHouse (Node C) instead
-- of Postgres/TimescaleDB for better performance and cost efficiency.
--
-- ClickHouse setup is handled by: infra/nixos/services/clickhouse.nix
-- Data ingestion is handled by: lib/uptrack/clickhouse/resilient_writer.ex
--
-- This file is kept for reference only and can be safely removed.

SELECT 'Uptrack uses ClickHouse for time-series data - this script is deprecated' AS status;
