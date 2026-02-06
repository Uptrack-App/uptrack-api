defmodule Uptrack.AppRepo.Migrations.CreateTeamInvitations do
  use Ecto.Migration

  def change do
    create table(:team_invitations, primary_key: false, prefix: "app") do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :role, :team_role, null: false, default: "editor"
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false

      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all),
        null: false

      add :invited_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Unique constraint: one active invitation per email per org
    create unique_index(:team_invitations, [:organization_id, :email], prefix: "app")
    create unique_index(:team_invitations, [:token], prefix: "app")
    create index(:team_invitations, [:expires_at], prefix: "app")

    # Distribute on Citus if available
    execute(
      """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'citus') THEN
          PERFORM create_distributed_table('app.team_invitations', 'organization_id', colocate_with => 'app.organizations');
        END IF;
      END $$;
      """,
      ""
    )
  end
end
