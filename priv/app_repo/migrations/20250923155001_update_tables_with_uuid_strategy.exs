defmodule Uptrack.AppRepo.Migrations.UpdateTablesWithUuidStrategy do
  use Ecto.Migration

  def up do
    # Create app schema if it doesn't exist
    execute("CREATE SCHEMA IF NOT EXISTS app")

    # Drop existing tables in reverse dependency order
    drop_if_exists table(:monitor_checks, prefix: :app)
    drop_if_exists table(:monitor_regions, prefix: :app)
    drop_if_exists table(:status_page_monitors, prefix: :app)
    drop_if_exists table(:status_pages, prefix: :app)
    drop_if_exists table(:incident_updates, prefix: :app)
    drop_if_exists table(:incidents, prefix: :app)
    drop_if_exists table(:alert_channels, prefix: :app)
    drop_if_exists table(:monitors, prefix: :app)
    drop_if_exists table(:users, prefix: :app)

    # Recreate with UUID strategy

    # Users table - UUID
    create table(:users, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :provider, :string
      add :provider_id, :string
      add :notification_preferences, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email], prefix: :app)
    create unique_index(:users, [:provider, :provider_id], prefix: :app)

    # Monitors table - UUID
    create table(:monitors, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :url, :string, null: false
      add :monitor_type, :string, null: false
      add :interval, :integer, default: 300
      add :timeout, :integer, default: 30
      add :status, :string, default: "active"
      add :description, :text
      add :settings, :map, default: %{}
      add :alert_contacts, {:array, :string}, default: []
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:monitors, [:user_id], prefix: :app)
    create index(:monitors, [:status], prefix: :app)

    # Monitor regions join table - aligns region distribution with UUID monitors
    create table(:monitor_regions, prefix: :app) do
      add :monitor_id, references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app), null: false
      add :region_id, references(:regions, on_delete: :delete_all, prefix: :app), null: false
      add :is_enabled, :boolean, default: true
      add :priority, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:monitor_regions, [:monitor_id, :region_id], prefix: :app)
    create index(:monitor_regions, [:monitor_id], prefix: :app)
    create index(:monitor_regions, [:region_id], prefix: :app)
    create index(:monitor_regions, [:is_enabled], prefix: :app)

    # Alert channels table - UUID
    create table(:alert_channels, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false
      add :config, :map, null: false
      add :is_active, :boolean, default: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:alert_channels, [:user_id], prefix: :app)
    create index(:alert_channels, [:type], prefix: :app)

    # Incidents table - UUID
    create table(:incidents, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :status, :string, null: false
      add :started_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime
      add :duration, :integer
      add :cause, :text
      add :monitor_id, references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app), null: false
      add :first_check_id, :bigint
      add :last_check_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:incidents, [:monitor_id], prefix: :app)
    create index(:incidents, [:status], prefix: :app)
    create index(:incidents, [:started_at], prefix: :app)

    # Incident updates table - Integer (high frequency)
    create table(:incident_updates, prefix: :app) do
      add :message, :text, null: false
      add :status, :string, null: false
      add :incident_id, references(:incidents, type: :uuid, on_delete: :delete_all, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:incident_updates, [:incident_id], prefix: :app)

    # Status pages table - UUID
    create table(:status_pages, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :custom_domain, :string
      add :is_public, :boolean, default: true
      add :theme, :string, default: "light"
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:status_pages, [:slug], prefix: :app)
    create index(:status_pages, [:user_id], prefix: :app)

    # Status page monitors (many-to-many) - Integer join table
    create table(:status_page_monitors, prefix: :app) do
      add :status_page_id, references(:status_pages, type: :uuid, on_delete: :delete_all, prefix: :app), null: false
      add :monitor_id, references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app), null: false
      add :display_order, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:status_page_monitors, [:status_page_id, :monitor_id], prefix: :app)

    # Monitor checks table - Integer (high volume, performance critical)
    create table(:monitor_checks, prefix: :app) do
      add :status, :string, null: false
      add :response_time, :integer
      add :checked_at, :utc_datetime, null: false
      add :error_message, :text
      add :status_code, :integer
      add :monitor_id, references(:monitors, type: :uuid, on_delete: :delete_all, prefix: :app), null: false
      add :region_id, references(:regions, on_delete: :restrict, prefix: :app)

      timestamps(type: :utc_datetime)
    end

    create index(:monitor_checks, [:monitor_id, :checked_at], prefix: :app)
    create index(:monitor_checks, [:status], prefix: :app)
    create index(:monitor_checks, [:region_id], prefix: :app)
  end

  def down do
    # Drop all tables and let the original migration handle recreation
    drop table(:monitor_checks, prefix: :app)
    drop table(:status_page_monitors, prefix: :app)
    drop table(:status_pages, prefix: :app)
    drop table(:incident_updates, prefix: :app)
    drop table(:incidents, prefix: :app)
    drop table(:alert_channels, prefix: :app)
    drop table(:monitor_regions, prefix: :app)
    drop table(:monitors, prefix: :app)
    drop table(:users, prefix: :app)
  end
end
