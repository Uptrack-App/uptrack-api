defmodule Uptrack.AppRepo.Migrations.CascadeMaintenanceWindowsMonitorFk do
  use Ecto.Migration

  def up do
    drop constraint("maintenance_windows", "maintenance_windows_monitor_id_fkey", prefix: "app")

    alter table("maintenance_windows", prefix: "app") do
      modify :monitor_id,
             references(:monitors, prefix: "app", type: :binary_id, on_delete: :delete_all),
             null: true
    end
  end

  def down do
    drop constraint("maintenance_windows", "maintenance_windows_monitor_id_fkey", prefix: "app")

    alter table("maintenance_windows", prefix: "app") do
      modify :monitor_id,
             references(:monitors, prefix: "app", type: :binary_id),
             null: true
    end
  end
end
