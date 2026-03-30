defmodule Uptrack.AppRepo.Migrations.CreateTotpCredentials do
  use Ecto.Migration

  def change do
    create table(:totp_credentials, prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, prefix: "app", on_delete: :delete_all), null: false
      add :secret, :binary, null: false
      add :backup_codes, :jsonb, default: "[]"
      add :enabled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:totp_credentials, [:user_id], prefix: "app")
  end
end
