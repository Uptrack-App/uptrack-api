defmodule Uptrack.Repo.Migrations.CreateMonitoringSchema do
  use Ecto.Migration

  def change do
    # Monitors table - core monitoring configuration
    create table(:monitors) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :monitor_type, :string, null: false, default: "http"
      # seconds
      add :interval, :integer, null: false, default: 300
      # seconds
      add :timeout, :integer, null: false, default: 30
      add :status, :string, null: false, default: "active"
      add :description, :text
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :alert_contacts, :map, default: %{}
      # Store monitor-specific settings like headers, keywords, etc.
      add :settings, :map, default: %{}

      timestamps()
    end

    create index(:monitors, [:user_id])
    create index(:monitors, [:status])
    create index(:monitors, [:monitor_type])

    # Monitor checks table - individual ping results
    create table(:monitor_checks) do
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
      # "up", "down", "paused"
      add :status, :string, null: false
      # milliseconds
      add :response_time, :integer
      add :status_code, :integer
      add :checked_at, :utc_datetime, null: false
      add :error_message, :text
      add :response_body, :text
      add :response_headers, :map

      timestamps()
    end

    create index(:monitor_checks, [:monitor_id])
    create index(:monitor_checks, [:checked_at])
    create index(:monitor_checks, [:status])

    # Incidents table - downtime tracking
    create table(:incidents) do
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime
      # "ongoing", "resolved"
      add :status, :string, null: false, default: "ongoing"
      # seconds, calculated when resolved
      add :duration, :integer
      add :cause, :text
      add :first_check_id, references(:monitor_checks, on_delete: :nilify_all)
      add :last_check_id, references(:monitor_checks, on_delete: :nilify_all)

      timestamps()
    end

    create index(:incidents, [:monitor_id])
    create index(:incidents, [:status])
    create index(:incidents, [:started_at])

    # Alert channels table - notification methods
    create table(:alert_channels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # "email", "slack", "webhook", "sms"
      add :type, :string, null: false
      add :name, :string, null: false
      # Store channel-specific config (email, webhook URL, etc.)
      add :config, :map, null: false
      add :is_active, :boolean, default: true

      timestamps()
    end

    create index(:alert_channels, [:user_id])
    create index(:alert_channels, [:type])

    # Alert logs table - track sent notifications
    create table(:alert_logs) do
      add :incident_id, references(:incidents, on_delete: :delete_all), null: false
      add :alert_channel_id, references(:alert_channels, on_delete: :delete_all), null: false
      # "sent", "failed", "pending"
      add :status, :string, null: false
      add :sent_at, :utc_datetime
      add :error_message, :text

      timestamps()
    end

    create index(:alert_logs, [:incident_id])
    create index(:alert_logs, [:alert_channel_id])

    # Status pages table - public status pages
    create table(:status_pages) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :is_public, :boolean, default: true
      add :custom_domain, :string
      add :logo_url, :string
      add :theme_config, :map, default: %{}

      timestamps()
    end

    create unique_index(:status_pages, [:slug])
    create index(:status_pages, [:user_id])

    # Status page monitors - which monitors to show on status page
    create table(:status_page_monitors) do
      add :status_page_id, references(:status_pages, on_delete: :delete_all), null: false
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
      add :display_name, :string
      add :sort_order, :integer, default: 0

      timestamps()
    end

    create unique_index(:status_page_monitors, [:status_page_id, :monitor_id])
    create index(:status_page_monitors, [:status_page_id])

    # Maintenance windows table - scheduled maintenance
    create table(:maintenance_windows) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      # "scheduled", "ongoing", "completed"
      add :status, :string, null: false, default: "scheduled"

      timestamps()
    end

    create index(:maintenance_windows, [:user_id])
    create index(:maintenance_windows, [:starts_at])
    create index(:maintenance_windows, [:status])

    # Maintenance window monitors - which monitors are affected
    create table(:maintenance_window_monitors) do
      add :maintenance_window_id, references(:maintenance_windows, on_delete: :delete_all),
        null: false

      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:maintenance_window_monitors, [:maintenance_window_id, :monitor_id])
  end
end
