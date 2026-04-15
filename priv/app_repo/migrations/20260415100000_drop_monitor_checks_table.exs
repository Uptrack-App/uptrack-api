defmodule Uptrack.AppRepo.Migrations.DropMonitorChecksTable do
  use Ecto.Migration

  def up do
    # Remove FK-like columns from incidents (no actual FK constraint exists)
    alter table(:incidents, prefix: "app") do
      remove :first_check_id
      remove :last_check_id
    end

    drop table(:monitor_checks, prefix: "app")
  end

  def down do
    create table(:monitor_checks, prefix: "app") do
      add :monitor_id, :bigint, null: false
      add :status, :string, null: false
      add :response_time, :integer
      add :status_code, :integer
      add :error_message, :text
      add :response_body, :text
      add :response_headers, :map
      add :region, :string
      add :checked_at, :utc_datetime, null: false
      timestamps()
    end

    alter table(:incidents, prefix: "app") do
      add :first_check_id, :bigint
      add :last_check_id, :bigint
    end
  end
end
