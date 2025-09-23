defmodule Uptrack.ResultsRepo do
  use Ecto.Repo,
    otp_app: :uptrack,
    adapter: Ecto.Adapters.Postgres

  @doc """
  ResultsRepo handles time-series monitoring data:
  - Monitor check results (hypertables by user tier)
  - TimescaleDB continuous aggregates (rollups)
  - Compression and retention policies
  - High-volume monitoring metrics

  This repo points to the 'results' schema with TimescaleDB
  enabled for efficient time-series data management.

  Hypertables:
  - monitor_results_free (120d retention)
  - monitor_results_solo (455d retention)
  - monitor_results_team (455d retention)
  """
end