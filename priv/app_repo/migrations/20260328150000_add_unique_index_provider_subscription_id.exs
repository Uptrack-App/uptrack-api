defmodule Uptrack.AppRepo.Migrations.AddUniqueIndexProviderSubscriptionId do
  use Ecto.Migration

  def change do
    # Idempotent: index was applied manually on production during Creem→Paddle switch.
    # Partial index excludes NULLs since legacy Paddle subscriptions use paddle_subscription_id field.
    create_if_not_exists unique_index(:subscriptions, [:provider_subscription_id],
      prefix: "app",
      name: "subscriptions_provider_subscription_id_unique",
      where: "provider_subscription_id IS NOT NULL"
    )
  end
end
