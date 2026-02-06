defmodule Uptrack.AppRepo.Migrations.AddStatusPageSubscribers do
  use Ecto.Migration

  def change do
    create table(:status_page_subscribers, prefix: "app", primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :status_page_id, references(:status_pages, type: :uuid, on_delete: :delete_all), null: false
      add :verified, :boolean, default: false, null: false
      add :verification_token, :string
      add :verification_sent_at, :utc_datetime
      add :unsubscribe_token, :string, null: false
      add :subscribed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Unique constraint on email per status page
    create unique_index(:status_page_subscribers, [:status_page_id, :email], prefix: "app")

    # Index for token lookups
    create index(:status_page_subscribers, [:verification_token], prefix: "app")
    create index(:status_page_subscribers, [:unsubscribe_token], prefix: "app")

    # Index for listing subscribers
    create index(:status_page_subscribers, [:status_page_id, :verified], prefix: "app")

    # Add subscriber settings to status pages
    alter table(:status_pages, prefix: "app") do
      add :allow_subscriptions, :boolean, default: false, null: false
    end
  end
end
