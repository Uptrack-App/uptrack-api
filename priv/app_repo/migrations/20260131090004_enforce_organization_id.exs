defmodule Uptrack.AppRepo.Migrations.EnforceOrganizationId do
  use Ecto.Migration

  def up do
    # Make organization_id NOT NULL on all tables
    # This ensures data integrity after backfill

    alter table(:users, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end

    alter table(:monitors, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end

    alter table(:alert_channels, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end

    alter table(:status_pages, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end

    alter table(:incidents, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end
  end

  def down do
    # Allow NULL again for rollback
    alter table(:incidents, prefix: :app) do
      modify :organization_id, :uuid, null: true
    end

    alter table(:status_pages, prefix: :app) do
      modify :organization_id, :uuid, null: true
    end

    alter table(:alert_channels, prefix: :app) do
      modify :organization_id, :uuid, null: true
    end

    alter table(:monitors, prefix: :app) do
      modify :organization_id, :uuid, null: true
    end

    alter table(:users, prefix: :app) do
      modify :organization_id, :uuid, null: true
    end
  end
end
