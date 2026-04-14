defmodule Uptrack.AppRepo.Migrations.AddPreferredLocaleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users, prefix: "app") do
      add :preferred_locale, :string, null: false, default: "en"
    end
  end
end
