defmodule Uptrack.AppRepo.Migrations.CreateSmsQuotas do
  use Ecto.Migration

  def change do
    create table(:sms_quotas, prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, prefix: "app", on_delete: :delete_all), null: false
      add :month, :string, null: false
      add :used_count, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sms_quotas, [:organization_id, :month], prefix: "app")
  end
end
