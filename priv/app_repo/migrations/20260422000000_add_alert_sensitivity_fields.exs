defmodule Uptrack.AppRepo.Migrations.AddAlertSensitivityFields do
  use Ecto.Migration

  def up do
    alter table("monitors", prefix: "app") do
      add :confirmation_window, :text, null: false, default: "3m"
      add :regions_required, :text, null: false, default: "majority"
    end

    create constraint("monitors", :confirmation_window_must_be_enum,
             prefix: "app",
             check: "confirmation_window IN ('1m', '3m', '5m', '10m')"
           )

    create constraint("monitors", :regions_required_must_be_enum,
             prefix: "app",
             check: "regions_required IN ('any', 'majority', 'all')"
           )

    alter table("incidents", prefix: "app") do
      add :alert_level, :text, null: true
    end

    create constraint("incidents", :alert_level_must_be_enum,
             prefix: "app",
             check: "alert_level IS NULL OR alert_level IN ('warn', 'page', 'critical', 'flapping')"
           )
  end

  def down do
    drop constraint("incidents", :alert_level_must_be_enum, prefix: "app")

    alter table("incidents", prefix: "app") do
      remove :alert_level
    end

    drop constraint("monitors", :regions_required_must_be_enum, prefix: "app")
    drop constraint("monitors", :confirmation_window_must_be_enum, prefix: "app")

    alter table("monitors", prefix: "app") do
      remove :regions_required
      remove :confirmation_window
    end
  end
end
