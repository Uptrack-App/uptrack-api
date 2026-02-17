defmodule Uptrack.Escalation.EscalationStep do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Escalation.EscalationPolicy
  alias Uptrack.Monitoring.AlertChannel

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "escalation_steps" do
    field :step_order, :integer
    field :delay_minutes, :integer, default: 0

    belongs_to :escalation_policy, EscalationPolicy
    belongs_to :alert_channel, AlertChannel

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:step_order, :delay_minutes, :escalation_policy_id, :alert_channel_id])
    |> validate_required([:step_order, :delay_minutes, :escalation_policy_id, :alert_channel_id])
    |> validate_number(:step_order, greater_than_or_equal_to: 1)
    |> validate_number(:delay_minutes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:escalation_policy_id)
    |> foreign_key_constraint(:alert_channel_id)
  end
end
