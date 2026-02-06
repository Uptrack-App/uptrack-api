defmodule Uptrack.AppRepo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  def up do
    # Create role enum type
    execute """
    CREATE TYPE app.team_role AS ENUM ('owner', 'admin', 'editor', 'viewer', 'notify_only')
    """

    # Add role column to users
    alter table(:users, prefix: "app") do
      add :role, :team_role, null: false, default: "owner"
    end

    # Add index for role lookups
    create index(:users, [:organization_id, :role], prefix: "app")
  end

  def down do
    drop index(:users, [:organization_id, :role], prefix: "app")

    alter table(:users, prefix: "app") do
      remove :role
    end

    execute "DROP TYPE app.team_role"
  end
end
