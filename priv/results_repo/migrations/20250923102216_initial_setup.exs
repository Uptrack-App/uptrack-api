defmodule Uptrack.ResultsRepo.Migrations.InitialSetup do
  use Ecto.Migration

  def up do
    # Create results schema (used for app-level metadata only)
    # Actual time-series data is stored in ClickHouse
    execute("CREATE SCHEMA IF NOT EXISTS results")

    # NOTE: Monitor check results are now stored in ClickHouse (Node C)
    # This schema is reserved for:
    # - Future app-level result metadata (if needed)
    # - Postgres-backed features that complement ClickHouse
    #
    # See: lib/uptrack/clickhouse/resilient_writer.ex for data ingestion
    # See: infra/nixos/services/clickhouse.nix for ClickHouse schema
  end

  def down do
    execute("DROP SCHEMA IF EXISTS results CASCADE")
  end
end