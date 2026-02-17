defmodule Uptrack.Escalation.EscalationPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization
  alias Uptrack.Escalation.EscalationStep

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "escalation_policies" do
    field :name, :string
    field :description, :string

    belongs_to :organization, Organization
    has_many :steps, EscalationStep, preload_order: [asc: :step_order]

    timestamps(type: :utc_datetime)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :description, :organization_id])
    |> validate_required([:name, :organization_id])
    |> foreign_key_constraint(:organization_id)
  end
end
