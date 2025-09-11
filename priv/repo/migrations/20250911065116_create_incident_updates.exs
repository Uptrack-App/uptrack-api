defmodule Uptrack.Repo.Migrations.CreateIncidentUpdates do
  use Ecto.Migration

  def change do
    create table(:incident_updates) do
      add :incident_id, references(:incidents, on_delete: :delete_all), null: false
      # investigating, identified, monitoring, resolved
      add :status, :string, null: false, default: "investigating"
      add :title, :string, null: false
      add :description, :text, null: false
      add :posted_at, :utc_datetime, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:incident_updates, [:incident_id])
    create index(:incident_updates, [:posted_at])
    create index(:incident_updates, [:status])
  end
end
