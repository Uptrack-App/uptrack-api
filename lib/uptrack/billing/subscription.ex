defmodule Uptrack.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias Uptrack.Organizations.Organization

  @valid_statuses ~w(active trialing cancelled past_due)
  @valid_providers ~w(paddle)

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "subscriptions" do
    field :paddle_subscription_id, :string
    field :paddle_customer_id, :string
    field :provider, :string, default: "paddle"
    field :provider_subscription_id, :string
    field :provider_customer_id, :string
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
      :provider,
      :provider_subscription_id,
      :provider_customer_id,
      :plan,
      :status,
      :current_period_start,
      :current_period_end,
      :cancelled_at
    ])
    |> validate_required([:organization_id, :plan])
    |> validate_at_least_one_subscription_id()
    |> validate_inclusion(:plan, Uptrack.Billing.paid_plans())
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:provider, @valid_providers)
    |> unique_constraint(:paddle_subscription_id)
    |> unique_constraint(:provider_subscription_id)
    |> foreign_key_constraint(:organization_id)
  end

  defp validate_at_least_one_subscription_id(changeset) do
    paddle_id = get_field(changeset, :paddle_subscription_id)
    provider_id = get_field(changeset, :provider_subscription_id)

    if is_nil(paddle_id) and is_nil(provider_id) do
      add_error(changeset, :provider_subscription_id, "either paddle_subscription_id or provider_subscription_id is required")
    else
      changeset
    end
  end
end
