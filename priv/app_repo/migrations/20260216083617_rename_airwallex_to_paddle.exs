defmodule Uptrack.AppRepo.Migrations.RenameAirwallexToPaddle do
  use Ecto.Migration

  def change do
    rename table("subscriptions", prefix: "app"), :airwallex_subscription_id, to: :paddle_subscription_id
    rename table("subscriptions", prefix: "app"), :airwallex_customer_id, to: :paddle_customer_id

    # Drop old indexes and create new ones with updated names
    drop_if_exists unique_index("subscriptions", [:airwallex_subscription_id], prefix: "app")
    drop_if_exists unique_index("subscriptions", [:airwallex_customer_id], prefix: "app")

    create unique_index("subscriptions", [:paddle_subscription_id], prefix: "app")
    create unique_index("subscriptions", [:paddle_customer_id], prefix: "app")
  end
end
