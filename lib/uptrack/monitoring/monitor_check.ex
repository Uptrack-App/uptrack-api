defmodule Uptrack.Monitoring.MonitorCheck do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Monitoring.{Monitor, Region}

  @statuses ~w(up down paused)

  @schema_prefix "app"
  schema "monitor_checks" do
    field :status, :string
    field :response_time, :integer
    field :status_code, :integer
    field :checked_at, :utc_datetime
    field :error_message, :string
    field :response_body, :string
    field :response_headers, :map
    field :check_region, :string, source: :region
    field :region_results, :map

    belongs_to :monitor, Monitor, type: Uniq.UUID
    belongs_to :region, Region

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(monitor_check, attrs) do
    monitor_check
    |> cast(attrs, [
      :status,
      :response_time,
      :status_code,
      :checked_at,
      :error_message,
      :response_body,
      :response_headers,
      :check_region,
      :region_results,
      :monitor_id,
      :region_id
    ])
    |> validate_required([:status, :checked_at, :monitor_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:response_time, greater_than_or_equal_to: 0)
    |> validate_number(:status_code, greater_than_or_equal_to: 100, less_than: 600)
    |> foreign_key_constraint(:monitor_id)
    |> foreign_key_constraint(:region_id)
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> maybe_set_checked_at()
  end

  defp maybe_set_checked_at(changeset) do
    case get_change(changeset, :checked_at) do
      nil -> put_change(changeset, :checked_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  def statuses, do: @statuses
end
