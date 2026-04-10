defmodule Uptrack.AppRepo.Migrations.AddRegionResultsToMonitorChecks do
  use Ecto.Migration

  def change do
    alter table(:monitor_checks, prefix: "app") do
      add_if_not_exists :region, :string
      add_if_not_exists :region_results, :map
    end
  end
end
