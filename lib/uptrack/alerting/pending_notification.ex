defmodule Uptrack.Alerting.PendingNotification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{Incident, Monitor}
  alias Uptrack.Accounts.User

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "pending_notifications" do
    field :event_type, :string
    field :recipient_email, :string
    field :delivered, :boolean, default: false

    belongs_to :incident, Incident
    belongs_to :monitor, Monitor
    belongs_to :user, User
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(pending_notification, attrs) do
    pending_notification
    |> cast(attrs, [
      :event_type,
      :recipient_email,
      :incident_id,
      :monitor_id,
      :user_id,
      :organization_id,
      :delivered
    ])
    |> validate_required([
      :event_type,
      :recipient_email,
      :incident_id,
      :monitor_id,
      :user_id,
      :organization_id
    ])
    |> validate_inclusion(:event_type, ["incident_created", "incident_resolved"])
    |> foreign_key_constraint(:incident_id)
    |> foreign_key_constraint(:monitor_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
