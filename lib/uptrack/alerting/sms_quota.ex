defmodule Uptrack.Alerting.SmsQuota do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "sms_quotas" do
    field :month, :string
    field :used_count, :integer, default: 0

    belongs_to :organization, Uptrack.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(quota, attrs) do
    quota
    |> cast(attrs, [:organization_id, :month, :used_count])
    |> validate_required([:organization_id, :month])
    |> unique_constraint([:organization_id, :month])
  end
end
