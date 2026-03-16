defmodule Uptrack.AppRepo.Migrations.AddProviderColumnsToSubscriptions do
  use Ecto.Migration

  @prefix "app"

  def change do
    alter table(:subscriptions, prefix: @prefix) do
      add :provider, :string, default: "paddle"
      add :provider_subscription_id, :string
      add :provider_customer_id, :string
    end

    create index(:subscriptions, [:provider_subscription_id], prefix: @prefix)
    create index(:subscriptions, [:provider], prefix: @prefix)
  end
end
