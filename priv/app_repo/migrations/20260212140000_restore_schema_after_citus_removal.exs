defmodule Uptrack.AppRepo.Migrations.RestoreSchemaAfterCitusRemoval do
  use Ecto.Migration

  @moduledoc """
  Restores columns, tables, and FK constraints that were lost when
  Citus distribution was removed via undistribute_table().

  Specifically:
  - Re-adds organization_id to users, monitors, alert_channels, status_pages, incidents
  - Recreates monitor_regions join table
  - Re-adds region_id to monitor_checks
  - Adds FK constraints that were dropped or never created due to Citus
  """

  def up do
    # 1. Add organization_id to tables that lost it during undistribution
    for table <- [:users, :monitors, :alert_channels, :status_pages, :incidents] do
      alter table(table, prefix: :app) do
        add :organization_id,
            references(:organizations, type: :uuid, on_delete: :delete_all, prefix: :app)
      end

      create index(table, [:organization_id], prefix: :app)
    end

    # 2. Recreate monitor_regions join table
    create table(:monitor_regions, prefix: :app) do
      add :monitor_id,
          references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app),
          null: false

      add :region_id,
          references(:regions, on_delete: :delete_all, prefix: :app),
          null: false

      add :is_enabled, :boolean, default: true
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:monitor_regions, [:monitor_id, :region_id], prefix: :app)
    create index(:monitor_regions, [:monitor_id], prefix: :app)
    create index(:monitor_regions, [:region_id], prefix: :app)
    create index(:monitor_regions, [:is_enabled], prefix: :app)

    # 3. Add region_id to monitor_checks
    alter table(:monitor_checks, prefix: :app) do
      add :region_id, references(:regions, on_delete: :restrict, prefix: :app)
    end

    create index(:monitor_checks, [:region_id], prefix: :app)
    create index(:monitor_checks, [:monitor_id, :region_id, :checked_at], prefix: :app)

    # 4. Add missing FK constraints on tables created during Citus era
    alter table(:team_invitations, prefix: :app) do
      modify :invited_by_id, references(:users, type: :uuid, on_delete: :nilify_all, prefix: :app),
        from: :uuid
    end

    alter table(:audit_logs, prefix: :app) do
      modify :user_id, references(:users, type: :uuid, on_delete: :nilify_all, prefix: :app),
        from: :uuid
    end

    alter table(:status_page_subscribers, prefix: :app) do
      modify :status_page_id,
             references(:status_pages, type: :uuid, on_delete: :delete_all, prefix: :app),
        from: :uuid
    end

    alter table(:api_keys, prefix: :app) do
      modify :created_by_id, references(:users, type: :uuid, prefix: :app), from: :uuid
    end

    alter table(:notification_deliveries, prefix: :app) do
      modify :incident_id,
             references(:incidents, type: :uuid, on_delete: :nilify_all, prefix: :app),
        from: :uuid

      modify :monitor_id,
             references(:monitors, type: :uuid, on_delete: :nilify_all, prefix: :app),
        from: :uuid

      modify :alert_channel_id,
             references(:alert_channels, type: :uuid, on_delete: :nilify_all, prefix: :app),
        from: :uuid
    end

    alter table(:pending_notifications, prefix: :app) do
      modify :incident_id,
             references(:incidents, type: :uuid, on_delete: :delete_all, prefix: :app),
        from: :uuid

      modify :monitor_id,
             references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app),
        from: :uuid

      modify :user_id,
             references(:users, type: :uuid, on_delete: :delete_all, prefix: :app),
        from: :uuid
    end
  end

  def down do
    # Remove FKs from later tables
    drop constraint(:pending_notifications, "pending_notifications_user_id_fkey", prefix: :app)
    drop constraint(:pending_notifications, "pending_notifications_monitor_id_fkey", prefix: :app)
    drop constraint(:pending_notifications, "pending_notifications_incident_id_fkey", prefix: :app)
    drop constraint(:notification_deliveries, "notification_deliveries_alert_channel_id_fkey", prefix: :app)
    drop constraint(:notification_deliveries, "notification_deliveries_monitor_id_fkey", prefix: :app)
    drop constraint(:notification_deliveries, "notification_deliveries_incident_id_fkey", prefix: :app)
    drop constraint(:api_keys, "api_keys_created_by_id_fkey", prefix: :app)
    drop constraint(:status_page_subscribers, "status_page_subscribers_status_page_id_fkey", prefix: :app)
    drop constraint(:audit_logs, "audit_logs_user_id_fkey", prefix: :app)
    drop constraint(:team_invitations, "team_invitations_invited_by_id_fkey", prefix: :app)

    # Remove region_id from monitor_checks
    drop index(:monitor_checks, [:monitor_id, :region_id, :checked_at], prefix: :app)
    drop index(:monitor_checks, [:region_id], prefix: :app)

    alter table(:monitor_checks, prefix: :app) do
      remove :region_id
    end

    # Drop monitor_regions
    drop table(:monitor_regions, prefix: :app)

    # Remove organization_id from tables
    for table <- [:incidents, :status_pages, :alert_channels, :monitors, :users] do
      drop index(table, [:organization_id], prefix: :app)

      alter table(table, prefix: :app) do
        remove :organization_id
      end
    end
  end
end
