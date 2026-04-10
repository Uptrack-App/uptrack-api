defmodule Uptrack.AppRepo.Migrations.CreateMagicLinkTokens do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:magic_link_tokens, prefix: "app", primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, null: false
      add :hashed_token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:magic_link_tokens, [:email, :hashed_token], prefix: "app")
    create_if_not_exists index(:magic_link_tokens, [:expires_at], prefix: "app")
  end
end
