defmodule Uptrack.AppRepo.Migrations.AddResourceAndSubToOauthTokens do
  use Ecto.Migration

  def change do
    # Boruta may already have `sub` — only add if missing
    alter table(:oauth_tokens) do
      add_if_not_exists :resource, :string
    end

    create_if_not_exists index(:oauth_tokens, [:sub])
  end
end
