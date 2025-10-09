defmodule Uptrack.Monitoring.IncidentUpdate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Accounts.User
  alias Uptrack.Monitoring.Incident

  @valid_statuses ~w[investigating identified monitoring resolved]

  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "incident_updates" do
    field :status, :string, default: "investigating"
    field :title, :string
    field :description, :string
    field :posted_at, :utc_datetime

    belongs_to :incident, Incident
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(incident_update, attrs) do
    incident_update
    |> cast(attrs, [:status, :title, :description, :posted_at, :incident_id, :user_id])
    |> validate_required([:status, :title, :description, :posted_at, :incident_id, :user_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, min: 1, max: 5000)
    |> maybe_set_posted_at()
  end

  defp maybe_set_posted_at(changeset) do
    case get_change(changeset, :posted_at) do
      nil -> put_change(changeset, :posted_at, DateTime.utc_now())
      _ -> changeset
    end
  end

  def status_options do
    [
      {"🔍 Investigating", "investigating"},
      {"🎯 Identified", "identified"},
      {"👁️ Monitoring", "monitoring"},
      {"✅ Resolved", "resolved"}
    ]
  end

  def status_color("investigating"), do: "badge-warning"
  def status_color("identified"), do: "badge-info"
  def status_color("monitoring"), do: "badge-primary"
  def status_color("resolved"), do: "badge-success"
  def status_color(_), do: "badge-neutral"

  def status_text("investigating"), do: "Investigating"
  def status_text("identified"), do: "Identified"
  def status_text("monitoring"), do: "Monitoring"
  def status_text("resolved"), do: "Resolved"
  def status_text(_), do: "Unknown"
end
