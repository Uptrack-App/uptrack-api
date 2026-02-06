defmodule Uptrack.AppRepo.Migrations.AddDefaultLanguageToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add :default_language, :string, default: "en", null: false
    end
  end
end
