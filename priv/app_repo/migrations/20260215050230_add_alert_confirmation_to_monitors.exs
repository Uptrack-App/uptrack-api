defmodule Uptrack.AppRepo.Migrations.AddAlertConfirmationToMonitors do
  use Ecto.Migration

  def change do
    alter table("monitors", prefix: "app") do
      add :consecutive_failures, :integer, default: 0, null: false
      add :confirmation_threshold, :integer, default: 2, null: false
    end
  end
end
