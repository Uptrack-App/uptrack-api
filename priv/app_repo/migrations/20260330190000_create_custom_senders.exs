defmodule Uptrack.AppRepo.Migrations.CreateCustomSenders do
  use Ecto.Migration

  def change do
    create table(:custom_senders, prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, prefix: "app", on_delete: :delete_all), null: false
      add :sender_name, :string, null: false
      add :sender_email, :string, null: false
      add :verified, :boolean, default: false, null: false
      add :verification_token, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:custom_senders, [:organization_id], prefix: "app")
    create unique_index(:custom_senders, [:verification_token], prefix: "app", where: "verification_token IS NOT NULL")
  end
end
