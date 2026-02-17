defmodule Uptrack.Maintenance.MaintenanceWindow do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.Monitor

  @recurrence_types ~w(none daily weekly monthly)
  @statuses ~w(scheduled active completed)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "maintenance_windows" do
    field :title, :string
    field :description, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :recurrence, :string, default: "none"
    field :status, :string, default: "scheduled"

    belongs_to :organization, Organization
    belongs_to :monitor, Monitor

    timestamps(type: :utc_datetime)
  end

  def changeset(window, attrs) do
    window
    |> cast(attrs, [
      :title,
      :description,
      :start_time,
      :end_time,
      :recurrence,
      :status,
      :organization_id,
      :monitor_id
    ])
    |> validate_required([:title, :start_time, :end_time, :organization_id])
    |> validate_inclusion(:recurrence, @recurrence_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_time_range()
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:monitor_id)
  end

  defp validate_time_range(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end

  def recurrence_types, do: @recurrence_types
  def statuses, do: @statuses
end
