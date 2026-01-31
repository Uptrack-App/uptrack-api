defmodule Uptrack.Monitoring.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{Monitor, MonitorCheck, IncidentUpdate}

  @statuses ~w(ongoing resolved)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "incidents" do
    field :started_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :status, :string, default: "ongoing"
    field :duration, :integer
    field :cause, :string

    belongs_to :organization, Organization
    belongs_to :monitor, Monitor
    belongs_to :first_check, MonitorCheck, type: :integer
    belongs_to :last_check, MonitorCheck, type: :integer
    has_many :incident_updates, IncidentUpdate, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :started_at,
      :resolved_at,
      :status,
      :duration,
      :cause,
      :monitor_id,
      :first_check_id,
      :last_check_id
    ])
    |> validate_required([:started_at, :monitor_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:duration, greater_than_or_equal_to: 0)
    |> validate_resolved_at()
    |> foreign_key_constraint(:monitor_id)
    |> foreign_key_constraint(:first_check_id)
    |> foreign_key_constraint(:last_check_id)
  end

  @doc false
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> put_change(:started_at, DateTime.utc_now())
    |> put_change(:status, "ongoing")
  end

  @doc false
  def resolve_changeset(incident, attrs \\ %{}) do
    resolved_at = DateTime.utc_now()

    duration =
      case incident.started_at do
        nil -> 0
        started_at -> DateTime.diff(resolved_at, started_at)
      end

    incident
    |> changeset(attrs)
    |> put_change(:resolved_at, resolved_at)
    |> put_change(:status, "resolved")
    |> put_change(:duration, duration)
  end

  defp validate_resolved_at(changeset) do
    started_at = get_field(changeset, :started_at)
    resolved_at = get_field(changeset, :resolved_at)

    case {started_at, resolved_at} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {started, resolved} ->
        if DateTime.compare(resolved, started) == :gt do
          changeset
        else
          add_error(changeset, :resolved_at, "must be after started_at")
        end
    end
  end

  def statuses, do: @statuses
end
