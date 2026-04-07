defmodule Uptrack.AppRepo.Migrations.AddNotificationDeliveries do
  use Ecto.Migration

  def change do
    create table(:notification_deliveries, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :channel_type, :string, null: false
      add :event_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :error_message, :text
      add :metadata, :map, default: %{}
      add :incident_id, references(:incidents, type: :uuid, prefix: :app, on_delete: :nilify_all)
      add :monitor_id, references(:monitors, type: :uuid, prefix: :app, on_delete: :nilify_all)
      add :alert_channel_id, references(:alert_channels, type: :uuid, prefix: :app, on_delete: :nilify_all)
      add :organization_id, references(:organizations, type: :uuid, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notification_deliveries, [:organization_id], prefix: :app)
    create index(:notification_deliveries, [:incident_id], prefix: :app)
    create index(:notification_deliveries, [:status], prefix: :app)
    create index(:notification_deliveries, [:organization_id, :inserted_at], prefix: :app)

    execute "GRANT ALL PRIVILEGES ON TABLE app.notification_deliveries TO uptrack_app_user"
  end
end
