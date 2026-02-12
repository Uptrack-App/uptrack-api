defmodule Uptrack.AppRepo.Migrations.AddResponseBodyToMonitorChecks do
  use Ecto.Migration

  def change do
    alter table(:monitor_checks, prefix: "app") do
      add :response_body, :text
      add :response_headers, :map
    end
  end
end
