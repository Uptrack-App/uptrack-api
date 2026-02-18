defmodule Uptrack.AppRepo.Migrations.DropPaddleCustomerIdUniqueIndex do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index("subscriptions", [:paddle_customer_id], prefix: "app")
    create index("subscriptions", [:paddle_customer_id], prefix: "app")
  end
end
