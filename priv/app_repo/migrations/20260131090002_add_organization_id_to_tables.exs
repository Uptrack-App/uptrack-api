defmodule Uptrack.AppRepo.Migrations.AddOrganizationIdToTables do
  use Ecto.Migration

  def up do
    # Add organization_id to users (nullable initially for backfill)
    alter table(:users, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app), null: true
    end

    create index(:users, [:organization_id], prefix: :app)

    # Add organization_id to monitors
    alter table(:monitors, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app), null: true
    end

    create index(:monitors, [:organization_id], prefix: :app)

    # Add organization_id to alert_channels
    alter table(:alert_channels, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app), null: true
    end

    create index(:alert_channels, [:organization_id], prefix: :app)

    # Add organization_id to status_pages
    alter table(:status_pages, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app), null: true
    end

    create index(:status_pages, [:organization_id], prefix: :app)

    # Add organization_id to incidents
    alter table(:incidents, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app), null: true
    end

    create index(:incidents, [:organization_id], prefix: :app)
  end

  def down do
    drop index(:incidents, [:organization_id], prefix: :app)
    drop index(:status_pages, [:organization_id], prefix: :app)
    drop index(:alert_channels, [:organization_id], prefix: :app)
    drop index(:monitors, [:organization_id], prefix: :app)
    drop index(:users, [:organization_id], prefix: :app)

    alter table(:incidents, prefix: :app) do
      remove :organization_id
    end

    alter table(:status_pages, prefix: :app) do
      remove :organization_id
    end

    alter table(:alert_channels, prefix: :app) do
      remove :organization_id
    end

    alter table(:monitors, prefix: :app) do
      remove :organization_id
    end

    alter table(:users, prefix: :app) do
      remove :organization_id
    end
  end
end
