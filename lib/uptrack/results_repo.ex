defmodule Uptrack.ResultsRepo do
  use Ecto.Repo,
    otp_app: :uptrack,
    adapter: Ecto.Adapters.Postgres

  @doc """
  ResultsRepo handles time-series monitoring metadata.

  NOTE: Actual check results are stored in ClickHouse (Node C) for better
  time-series performance and cost efficiency.

  This repo is reserved for:
  - Future app-level result metadata (e.g., result annotations, bookmarks)
  - Postgres-backed features that complement ClickHouse analytics
  - Relational data that doesn't fit ClickHouse's columnar model

  For writing check results, see: Uptrack.ClickHouse.ResilientWriter
  For ClickHouse schema, see: infra/nixos/services/clickhouse.nix
  """
end