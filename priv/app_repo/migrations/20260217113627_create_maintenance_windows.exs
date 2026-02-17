defmodule Uptrack.AppRepo.Migrations.CreateMaintenanceWindows do
  use Ecto.Migration

  def change do
    create table("maintenance_windows", prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, prefix: "app", type: :binary_id), null: false
      add :monitor_id, references(:monitors, prefix: "app", type: :binary_id), null: true
      add :title, :string, null: false
      add :description, :text
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false
      add :recurrence, :string, null: false, default: "none"
      add :status, :string, null: false, default: "scheduled"

      timestamps(type: :utc_datetime)
    end

    create index("maintenance_windows", [:organization_id], prefix: "app")
    create index("maintenance_windows", [:monitor_id], prefix: "app")
    create index("maintenance_windows", [:status], prefix: "app")
    create index("maintenance_windows", [:start_time, :end_time], prefix: "app")
  end
end
