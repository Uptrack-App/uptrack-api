defmodule Uptrack.Repo do
  use Ecto.Repo,
    otp_app: :uptrack,
    adapter: Ecto.Adapters.Postgres
end
