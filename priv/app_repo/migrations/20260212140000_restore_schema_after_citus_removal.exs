defmodule Uptrack.AppRepo.Migrations.RestoreSchemaAfterCitusRemoval do
  use Ecto.Migration

  @moduledoc """
  Restores columns, tables, and FK constraints that were lost when
  Citus distribution was removed via undistribute_table().

  All operations are idempotent (IF NOT EXISTS / IF EXISTS) so this
  migration works both on production (where columns were dropped) and
  on fresh databases (where earlier migrations already created them).
  """

  def up do
    # 1. Add organization_id to tables that lost it during undistribution
    for table <- ~w(users monitors alert_channels status_pages incidents) do
      execute """
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'app' AND table_name = '#{table}' AND column_name = 'organization_id'
        ) THEN
          ALTER TABLE app.#{table}
            ADD COLUMN organization_id uuid REFERENCES app.organizations(id) ON DELETE CASCADE;
        END IF;
      END $$;
      """

      execute """
      CREATE INDEX IF NOT EXISTS #{table}_organization_id_index ON app.#{table} (organization_id);
      """
    end

    # 2. Recreate monitor_regions join table
    execute """
    CREATE TABLE IF NOT EXISTS app.monitor_regions (
      id bigserial PRIMARY KEY,
      monitor_id uuid NOT NULL REFERENCES app.monitors(id) ON DELETE CASCADE,
      region_id bigint NOT NULL REFERENCES app.regions(id) ON DELETE CASCADE,
      is_enabled boolean DEFAULT true,
      priority integer DEFAULT 0,
      inserted_at timestamp(0) WITHOUT TIME ZONE NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
      updated_at timestamp(0) WITHOUT TIME ZONE NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
    );
    """

    execute "CREATE UNIQUE INDEX IF NOT EXISTS monitor_regions_monitor_id_region_id_index ON app.monitor_regions (monitor_id, region_id);"
    execute "CREATE INDEX IF NOT EXISTS monitor_regions_monitor_id_index ON app.monitor_regions (monitor_id);"
    execute "CREATE INDEX IF NOT EXISTS monitor_regions_region_id_index ON app.monitor_regions (region_id);"
    execute "CREATE INDEX IF NOT EXISTS monitor_regions_is_enabled_index ON app.monitor_regions (is_enabled);"

    # 3. Add region_id to monitor_checks
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'app' AND table_name = 'monitor_checks' AND column_name = 'region_id'
      ) THEN
        ALTER TABLE app.monitor_checks
          ADD COLUMN region_id bigint REFERENCES app.regions(id) ON DELETE RESTRICT;
      END IF;
    END $$;
    """

    execute "CREATE INDEX IF NOT EXISTS monitor_checks_region_id_index ON app.monitor_checks (region_id);"
    execute "CREATE INDEX IF NOT EXISTS monitor_checks_monitor_id_region_id_checked_at_index ON app.monitor_checks (monitor_id, region_id, checked_at);"

    # 4. Add missing FK constraints on tables created during Citus era
    # Use DO blocks to skip if constraint already exists
    add_fk_if_missing("team_invitations", "invited_by_id", "users", "team_invitations_invited_by_id_fkey")
    add_fk_if_missing("audit_logs", "user_id", "users", "audit_logs_user_id_fkey")
    add_fk_if_missing("status_page_subscribers", "status_page_id", "status_pages", "status_page_subscribers_status_page_id_fkey")
    add_fk_if_missing("api_keys", "created_by_id", "users", "api_keys_created_by_id_fkey")
    add_fk_if_missing("notification_deliveries", "incident_id", "incidents", "notification_deliveries_incident_id_fkey", on_delete: "SET NULL")
    add_fk_if_missing("notification_deliveries", "monitor_id", "monitors", "notification_deliveries_monitor_id_fkey", on_delete: "SET NULL")
    add_fk_if_missing("notification_deliveries", "alert_channel_id", "alert_channels", "notification_deliveries_alert_channel_id_fkey", on_delete: "SET NULL")
    add_fk_if_missing("pending_notifications", "incident_id", "incidents", "pending_notifications_incident_id_fkey")
    add_fk_if_missing("pending_notifications", "monitor_id", "monitors", "pending_notifications_monitor_id_fkey")
    add_fk_if_missing("pending_notifications", "user_id", "users", "pending_notifications_user_id_fkey")
  end

  def down do
    # Remove FKs from later tables
    for {table, constraint} <- [
      {"pending_notifications", "pending_notifications_user_id_fkey"},
      {"pending_notifications", "pending_notifications_monitor_id_fkey"},
      {"pending_notifications", "pending_notifications_incident_id_fkey"},
      {"notification_deliveries", "notification_deliveries_alert_channel_id_fkey"},
      {"notification_deliveries", "notification_deliveries_monitor_id_fkey"},
      {"notification_deliveries", "notification_deliveries_incident_id_fkey"},
      {"api_keys", "api_keys_created_by_id_fkey"},
      {"status_page_subscribers", "status_page_subscribers_status_page_id_fkey"},
      {"audit_logs", "audit_logs_user_id_fkey"},
      {"team_invitations", "team_invitations_invited_by_id_fkey"}
    ] do
      execute "ALTER TABLE app.#{table} DROP CONSTRAINT IF EXISTS #{constraint};"
    end

    # Remove region_id from monitor_checks
    execute "DROP INDEX IF EXISTS app.monitor_checks_monitor_id_region_id_checked_at_index;"
    execute "DROP INDEX IF EXISTS app.monitor_checks_region_id_index;"

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'app' AND table_name = 'monitor_checks' AND column_name = 'region_id'
      ) THEN
        ALTER TABLE app.monitor_checks DROP COLUMN region_id;
      END IF;
    END $$;
    """

    # Drop monitor_regions
    execute "DROP TABLE IF EXISTS app.monitor_regions;"

    # Remove organization_id from tables
    for table <- ~w(incidents status_pages alert_channels monitors users) do
      execute "DROP INDEX IF EXISTS app.#{table}_organization_id_index;"

      execute """
      DO $$
      BEGIN
        IF EXISTS (
          SELECT 1 FROM information_schema.columns
          WHERE table_schema = 'app' AND table_name = '#{table}' AND column_name = 'organization_id'
        ) THEN
          ALTER TABLE app.#{table} DROP COLUMN organization_id;
        END IF;
      END $$;
      """
    end
  end

  defp add_fk_if_missing(table, column, ref_table, constraint_name, opts \\ []) do
    on_delete = Keyword.get(opts, :on_delete, "CASCADE")

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_schema = 'app' AND constraint_name = '#{constraint_name}'
      ) THEN
        ALTER TABLE app.#{table}
          ADD CONSTRAINT #{constraint_name}
          FOREIGN KEY (#{column}) REFERENCES app.#{ref_table}(id)
          ON DELETE #{on_delete};
      END IF;
    END $$;
    """
  end
end
