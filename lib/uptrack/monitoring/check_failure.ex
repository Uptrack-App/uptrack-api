defmodule Uptrack.Monitoring.CheckFailure do
  @moduledoc """
  Per-failure detail log. Stores body, headers and error context only for
  DOWN checks so we can show debugging info in the dashboard without the
  write volume of every UP check.

  Rolling retention keeps this bounded; see `Uptrack.Monitoring.CheckFailures`
  for cleanup.
  """

  use Ecto.Schema

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "monitor_check_failures" do
    field :monitor_id, Uniq.UUID
    field :status_code, :integer
    field :response_time, :integer
    field :error_message, :string
    field :response_body, :string
    field :response_headers, :map
    field :checked_at, :utc_datetime_usec
  end
end
