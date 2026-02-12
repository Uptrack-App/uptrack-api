defmodule Uptrack.AppRepo.Migrations.AddApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :key_prefix, :string, null: false
      add :key_hash, :string, null: false
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: ["read", "write"]
      add :is_active, :boolean, default: true, null: false
      add :organization_id, references(:organizations, type: :uuid, prefix: :app), null: false
      add :created_by_id, references(:users, type: :uuid, prefix: :app), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:api_keys, [:organization_id], prefix: :app)
    create index(:api_keys, [:key_hash], prefix: :app, unique: true)
    create index(:api_keys, [:key_prefix], prefix: :app)
    create index(:api_keys, [:is_active], prefix: :app)
  end
end
