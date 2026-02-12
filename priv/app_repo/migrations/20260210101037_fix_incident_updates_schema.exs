defmodule Uptrack.AppRepo.Migrations.FixIncidentUpdatesSchema do
  use Ecto.Migration

  def up do
    # Add missing columns that the IncidentUpdate schema expects
    alter table(:incident_updates, prefix: :app) do
      add :title, :string
      add :description, :text
      add :posted_at, :utc_datetime
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all, prefix: :app)
    end

    # Backfill from existing message column
    execute """
    UPDATE app.incident_updates
    SET title = LEFT(message, 255),
        description = message,
        posted_at = inserted_at
    WHERE title IS NULL
    """

    # Now enforce NOT NULL on the backfilled columns
    alter table(:incident_updates, prefix: :app) do
      modify :title, :string, null: false
      modify :description, :text, null: false
      modify :posted_at, :utc_datetime, null: false
    end

    # Drop the old message column (schema no longer references it)
    alter table(:incident_updates, prefix: :app) do
      remove :message
    end

    create index(:incident_updates, [:user_id], prefix: :app)
  end

  def down do
    drop_if_exists index(:incident_updates, [:user_id], prefix: :app)

    alter table(:incident_updates, prefix: :app) do
      add :message, :text
    end

    # Restore message from description
    execute """
    UPDATE app.incident_updates
    SET message = description
    """

    alter table(:incident_updates, prefix: :app) do
      modify :message, :text, null: false
    end

    alter table(:incident_updates, prefix: :app) do
      remove :title
      remove :description
      remove :posted_at
      remove :user_id
    end
  end
end
