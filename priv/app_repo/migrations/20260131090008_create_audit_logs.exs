defmodule Uptrack.AppRepo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false, prefix: "app") do
      add :id, :uuid, primary_key: true

      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)

      # Action details
      add :action, :string, null: false
      add :resource_type, :string, null: false
      add :resource_id, :uuid
      add :metadata, :map, default: %{}

      # Request context
      add :ip_address, :string
      add :user_agent, :string

      # Only timestamp, no updated_at for immutable logs
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    # Index for querying logs by org + time (most common query)
    create index(:audit_logs, [:organization_id, :created_at], prefix: "app")

    # Index for filtering by action type
    create index(:audit_logs, [:organization_id, :action], prefix: "app")

    # Index for resource lookups
    create index(:audit_logs, [:organization_id, :resource_type, :resource_id], prefix: "app")

    # Distribute on Citus if available
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citus') THEN
          PERFORM create_distributed_table('app.audit_logs', 'organization_id', colocate_with => 'app.organizations');
        END IF;
      END $$;
      """,
      ""
    )
  end
end
