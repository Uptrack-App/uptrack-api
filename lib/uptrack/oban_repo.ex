defmodule Uptrack.ObanRepo do
  use Ecto.Repo,
    otp_app: :uptrack,
    adapter: Ecto.Adapters.Postgres

  @doc """
  ObanRepo handles job orchestration:
  - Oban job tables and state
  - Job scheduling and execution
  - Background task management

  This repo points to the 'oban' schema and should use
  PgBouncer in SESSION mode (not TRANSACTION) to support
  advisory locks and LISTEN/NOTIFY.
  """
end