defmodule Uptrack.AppRepo.Migrations.InitialSetup do
  use Ecto.Migration

  def up do
    # Create app schema
    execute("CREATE SCHEMA IF NOT EXISTS app")

    # Users table
    create table("app.users") do
      add :email, :string, null: false
      add :name, :string
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :provider, :string
      add :provider_id, :string
      add :notification_preferences, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index("app.users", [:email])
    create unique_index("app.users", [:provider, :provider_id])

    # Monitors table
    create table("app.monitors") do
      add :name, :string, null: false
      add :url, :string, null: false
      add :monitor_type, :string, null: false
      add :interval, :integer, default: 300
      add :timeout, :integer, default: 30
      add :status, :string, default: "active"
      add :description, :text
      add :settings, :map, default: %{}
      add :alert_contacts, {:array, :string}, default: []
      add :user_id, references("app.users", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index("app.monitors", [:user_id])
    create index("app.monitors", [:status])

    # Alert channels table
    create table("app.alert_channels") do
      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, null: false
      add :is_active, :boolean, default: true
      add :user_id, references("app.users", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index("app.alert_channels", [:user_id])
    create index("app.alert_channels", [:type])

    # Incidents table
    create table("app.incidents") do
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime
      add :duration, :integer
      add :cause, :text
      add :monitor_id, references("app.monitors", on_delete: :delete_all), null: false
      add :first_check_id, :bigint
      add :last_check_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index("app.incidents", [:monitor_id])
    create index("app.incidents", [:status])
    create index("app.incidents", [:started_at])

    # Incident updates table
    create table("app.incident_updates") do
      add :message, :text, null: false
      add :status, :string, null: false
      add :incident_id, references("app.incidents", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index("app.incident_updates", [:incident_id])

    # Status pages table
    create table("app.status_pages") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :custom_domain, :string
      add :is_public, :boolean, default: true
      add :theme, :string, default: "light"
      add :user_id, references("app.users", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("app.status_pages", [:slug])
    create index("app.status_pages", [:user_id])

    # Status page monitors (many-to-many)
    create table("app.status_page_monitors") do
      add :status_page_id, references("app.status_pages", on_delete: :delete_all), null: false
      add :monitor_id, references("app.monitors", on_delete: :delete_all), null: false
      add :display_order, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index("app.status_page_monitors", [:status_page_id, :monitor_id])

    # Monitor checks table (for basic check metadata, detailed results go to ResultsRepo)
    create table("app.monitor_checks") do
      add :status, :string, null: false
      add :response_time, :integer
      add :checked_at, :utc_datetime, null: false
      add :error_message, :text
      add :status_code, :integer
      add :monitor_id, references("app.monitors", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index("app.monitor_checks", [:monitor_id, :checked_at])
    create index("app.monitor_checks", [:status])
  end

  def down do
    drop table("app.monitor_checks")
    drop table("app.status_page_monitors")
    drop table("app.status_pages")
    drop table("app.incident_updates")
    drop table("app.incidents")
    drop table("app.alert_channels")
    drop table("app.monitors")
    drop table("app.users")
    execute("DROP SCHEMA IF EXISTS app CASCADE")
  end
end