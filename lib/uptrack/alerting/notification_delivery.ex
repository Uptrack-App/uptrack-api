defmodule Uptrack.Alerting.NotificationDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID

  @statuses ~w(pending delivered failed skipped)
  @event_types ~w(incident_created incident_resolved test)

  @schema_prefix "app"
  schema "notification_deliveries" do
    field :channel_type, :string
    field :event_type, :string
    field :status, :string, default: "pending"
    field :error_message, :string
    field :metadata, :map, default: %{}

    belongs_to :incident, Incident
    belongs_to :monitor, Monitor
    belongs_to :alert_channel, AlertChannel
    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :channel_type,
      :event_type,
      :status,
      :error_message,
      :metadata,
      :incident_id,
      :monitor_id,
      :alert_channel_id,
      :organization_id
    ])
    |> validate_required([:channel_type, :event_type, :status, :organization_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:event_type, @event_types)
    |> foreign_key_constraint(:organization_id)
  end
end
