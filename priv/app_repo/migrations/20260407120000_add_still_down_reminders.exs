defmodule Uptrack.AppRepo.Migrations.AddStillDownReminders do
  use Ecto.Migration

  def change do
    alter table(:monitors, prefix: "app") do
      add :reminder_interval_minutes, :integer
    end

    alter table(:incidents, prefix: "app") do
      add :last_reminder_sent_at, :utc_datetime
      add :reminder_count, :integer, default: 0, null: false
    end
  end
end
