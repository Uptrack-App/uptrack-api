defmodule Uptrack.AppRepo.Migrations.AddRegionResultsToMonitorChecks do
  use Ecto.Migration

  def change do
    alter table(:monitor_checks, prefix: "app") do
      add :region, :string
      add :region_results, :map
    end
  end
end
