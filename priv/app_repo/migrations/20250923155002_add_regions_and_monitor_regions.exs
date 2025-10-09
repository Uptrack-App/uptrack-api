defmodule Uptrack.AppRepo.Migrations.AddRegionsAndMonitorRegions do
  use Ecto.Migration

  def up do
    # Create app schema if it doesn't exist
    execute("CREATE SCHEMA IF NOT EXISTS app")

    # Create regions table
    create table(:regions, prefix: :app) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :provider, :string, null: false, default: "hetzner"
      add :is_active, :boolean, default: true
      add :endpoint_url, :string  # For future multi-provider support
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:regions, [:code], prefix: :app)
    create index(:regions, [:provider], prefix: :app)
    create index(:regions, [:is_active], prefix: :app)

    # Create monitor_regions join table
    create table(:monitor_regions, prefix: :app) do
      add :monitor_id, references(:monitors, on_delete: :delete_all, prefix: :app), null: false
      add :region_id, references(:regions, on_delete: :delete_all, prefix: :app), null: false
      add :is_enabled, :boolean, default: true
      add :priority, :integer, default: 0  # For future failover logic

      timestamps(type: :utc_datetime)
    end

    create unique_index(:monitor_regions, [:monitor_id, :region_id], prefix: :app)
    create index(:monitor_regions, [:monitor_id], prefix: :app)
    create index(:monitor_regions, [:region_id], prefix: :app)
    create index(:monitor_regions, [:is_enabled], prefix: :app)

    # Add region_id to monitor_checks table
    alter table(:monitor_checks, prefix: :app) do
      add :region_id, references(:regions, on_delete: :restrict, prefix: :app)
    end

    create index(:monitor_checks, [:region_id], prefix: :app)
    create index(:monitor_checks, [:monitor_id, :region_id, :checked_at], prefix: :app)

    # Insert initial Hetzner regions
    execute """
    INSERT INTO app.regions (code, name, provider, is_active, inserted_at, updated_at) VALUES
    ('eu-north-1', 'Europe (Helsinki)', 'hetzner', true, NOW(), NOW()),
    ('us-west-2', 'US West (Oregon)', 'hetzner', true, NOW(), NOW()),
    ('ap-southeast-1', 'Asia Pacific (Singapore)', 'hetzner', true, NOW(), NOW())
    """

    # Future regions (commented out):
    # ('us-east-1', 'US East (N. Virginia)', 'vultr', false, NOW(), NOW()),
    # ('sa-east-1', 'South America (São Paulo)', 'contabo', false, NOW(), NOW()),
    # ('ap-south-1', 'Asia Pacific (Mumbai)', 'linode', false, NOW(), NOW()),
    # ('ap-southeast-2', 'Asia Pacific (Sydney)', 'linode', false, NOW(), NOW()),
    # ('eu-west-1', 'Europe (London)', 'vultr', false, NOW(), NOW())
  end

  def down do
    drop index(:monitor_checks, [:monitor_id, :region_id, :checked_at], prefix: :app)
    drop index(:monitor_checks, [:region_id], prefix: :app)

    alter table(:monitor_checks, prefix: :app) do
      remove :region_id
    end

    drop table(:monitor_regions, prefix: :app)
    drop table(:regions, prefix: :app)
  end
end
