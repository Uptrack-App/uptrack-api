defmodule Uptrack.AppRepo.Migrations.DistributeTablesCitus do
  use Ecto.Migration

  @moduledoc """
  Distribute tables using Citus for horizontal scaling.

  This migration only runs if Citus extension is available.
  Tables are distributed by organization_id for tenant isolation.

  Distribution strategy:
  - organizations: distributed by id (tenant root)
  - users, monitors, alert_channels, status_pages, incidents: colocated by organization_id
  - regions: reference table (replicated to all nodes)
  - monitor_checks, incident_updates: stay local (high volume, derived from parent)
  """

  def up do
    if citus_available?() do
      # Distribute organizations table by id
      execute "SELECT create_distributed_table('app.organizations', 'id')"

      # Distribute tenant tables by organization_id, colocated with organizations
      execute "SELECT create_distributed_table('app.users', 'organization_id', colocate_with => 'app.organizations')"
      execute "SELECT create_distributed_table('app.monitors', 'organization_id', colocate_with => 'app.organizations')"
      execute "SELECT create_distributed_table('app.alert_channels', 'organization_id', colocate_with => 'app.organizations')"
      execute "SELECT create_distributed_table('app.status_pages', 'organization_id', colocate_with => 'app.organizations')"
      execute "SELECT create_distributed_table('app.incidents', 'organization_id', colocate_with => 'app.organizations')"

      # Make regions a reference table (replicated to all nodes)
      execute "SELECT create_reference_table('app.regions')"
    else
      # Log that Citus is not available
      execute "DO $$ BEGIN RAISE NOTICE 'Citus extension not available, skipping distribution'; END $$;"
    end
  end

  def down do
    if citus_available?() do
      # Undistribute tables (convert back to local)
      execute "SELECT undistribute_table('app.incidents')"
      execute "SELECT undistribute_table('app.status_pages')"
      execute "SELECT undistribute_table('app.alert_channels')"
      execute "SELECT undistribute_table('app.monitors')"
      execute "SELECT undistribute_table('app.users')"
      execute "SELECT undistribute_table('app.organizations')"
      execute "SELECT undistribute_table('app.regions')"
    end
  end

  defp citus_available? do
    # Check if Citus extension is installed
    result = repo().query("SELECT 1 FROM pg_extension WHERE extname = 'citus'", [])

    case result do
      {:ok, %{num_rows: 1}} -> true
      _ -> false
    end
  end
end
