defmodule Uptrack.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization

  @valid_plans ~w(pro team)
  @valid_statuses ~w(active cancelled past_due)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "subscriptions" do
    field :paddle_subscription_id, :string
    field :paddle_customer_id, :string
    field :plan, :string
    field :status, :string, default: "active"
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :cancelled_at, :utc_datetime

    belongs_to :organization, Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :organization_id,
      :paddle_subscription_id,
      :paddle_customer_id,
      :plan,
      :status,
      :current_period_start,
      :current_period_end,
      :cancelled_at
    ])
    |> validate_required([:organization_id, :paddle_subscription_id, :plan])
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:paddle_subscription_id)
    |> unique_constraint(:paddle_customer_id)
    |> foreign_key_constraint(:organization_id)
  end
end
