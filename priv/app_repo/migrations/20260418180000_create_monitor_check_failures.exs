defmodule Uptrack.AppRepo.Migrations.CreateMonitorCheckFailures do
  use Ecto.Migration

  def change do
    create table(:monitor_check_failures, prefix: "app") do
      add :monitor_id, :binary_id, null: false
      add :status_code, :integer
      add :response_time, :integer
      add :error_message, :text
      add :response_body, :text
      add :response_headers, :map
      add :checked_at, :utc_datetime_usec, null: false
    end

    create index(:monitor_check_failures, [:monitor_id, :checked_at],
             prefix: "app",
             using: :btree,
             name: :monitor_check_failures_monitor_checked_at_desc_idx,
             unique: false
           )
  end
end
