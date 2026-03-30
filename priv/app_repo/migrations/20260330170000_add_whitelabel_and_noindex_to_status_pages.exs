defmodule Uptrack.AppRepo.Migrations.AddWhitelabelAndNoindexToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add :whitelabel, :boolean, default: false, null: false
      add :noindex, :boolean, default: false, null: false
    end
  end
end
