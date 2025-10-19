defmodule Uptrack.Repo.Migrations.CreateObanSchema do
  use Ecto.Migration

  def up do
    # Create oban schema
    execute("CREATE SCHEMA IF NOT EXISTS oban")

    # Install Oban tables in oban schema
    Oban.Migration.up(prefix: "oban", version: 12)
  end

  def down do
    Oban.Migration.down(prefix: "oban", version: 1)
    execute("DROP SCHEMA IF EXISTS oban CASCADE")
  end
end
