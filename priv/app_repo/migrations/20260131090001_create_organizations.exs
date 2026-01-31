defmodule Uptrack.AppRepo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def up do
    create table(:organizations, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :plan, :string, default: "free"
      add :settings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug], prefix: :app)
  end

  def down do
    drop table(:organizations, prefix: :app)
  end
end
