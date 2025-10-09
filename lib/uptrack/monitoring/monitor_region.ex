defmodule Uptrack.Monitoring.MonitorRegion do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Monitoring.{Monitor, Region}

  @schema_prefix "app"
  schema "monitor_regions" do
    field :is_enabled, :boolean, default: true
    field :priority, :integer, default: 0

    belongs_to :monitor, Monitor, type: Uniq.UUID
    belongs_to :region, Region

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(monitor_region, attrs) do
    monitor_region
    |> cast(attrs, [:is_enabled, :priority, :monitor_id, :region_id])
    |> validate_required([:monitor_id, :region_id])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:monitor_id)
    |> foreign_key_constraint(:region_id)
    |> unique_constraint([:monitor_id, :region_id])
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:is_enabled, true)
  end

  @doc """
  Enables a region for a monitor.
  """
  def enable_changeset(monitor_region) do
    changeset(monitor_region, %{is_enabled: true})
  end

  @doc """
  Disables a region for a monitor.
  """
  def disable_changeset(monitor_region) do
    changeset(monitor_region, %{is_enabled: false})
  end
end
