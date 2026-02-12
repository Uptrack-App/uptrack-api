defmodule Uptrack.AppRepo.Migrations.CreatePendingNotifications do
  use Ecto.Migration

  def change do
    create table(:pending_notifications, prefix: "app", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :event_type, :string, null: false
      add :recipient_email, :string, null: false
      add :incident_id, references(:incidents, prefix: "app", type: :uuid, on_delete: :delete_all), null: false
      add :monitor_id, references(:monitors, prefix: "app", type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, prefix: "app", type: :uuid, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, prefix: "app", type: :uuid, on_delete: :delete_all), null: false
      add :delivered, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:pending_notifications, [:user_id, :delivered], prefix: "app")
    create index(:pending_notifications, [:organization_id], prefix: "app")
  end
end
