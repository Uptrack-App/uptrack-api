defmodule Uptrack.AppRepo.Migrations.CreateAddOns do
  use Ecto.Migration

  def change do
    create table(:add_ons, prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, prefix: "app", on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :quantity, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:add_ons, [:organization_id, :type], prefix: "app")
  end
end
