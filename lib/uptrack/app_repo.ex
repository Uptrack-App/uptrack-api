defmodule Uptrack.AppRepo do
  use Ecto.Repo,
    otp_app: :uptrack,
    adapter: Ecto.Adapters.Postgres

  @doc """
  AppRepo handles the main application data:
  - Users and accounts
  - Monitors and their configurations
  - Incidents and incident updates
  - Alert channels
  - Status pages
  - Billing and subscription data

  This repo points to the 'app' schema for clean separation.
  """
end