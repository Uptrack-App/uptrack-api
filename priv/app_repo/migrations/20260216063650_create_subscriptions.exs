defmodule Uptrack.AppRepo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table("subscriptions", prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, prefix: "app", type: :binary_id), null: false
      add :airwallex_subscription_id, :string, null: false
      add :airwallex_customer_id, :string, null: false
      add :plan, :string, null: false
      add :status, :string, null: false, default: "active"
      add :current_period_start, :utc_datetime
      add :current_period_end, :utc_datetime
      add :cancelled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index("subscriptions", [:organization_id], prefix: "app")
    create unique_index("subscriptions", [:airwallex_subscription_id], prefix: "app")
    create unique_index("subscriptions", [:airwallex_customer_id], prefix: "app")
  end
end
