defmodule Uptrack.AppRepo.Migrations.AddWhitelabelAndNoindexToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add_if_not_exists :whitelabel, :boolean, default: false, null: false
      add_if_not_exists :noindex, :boolean, default: false, null: false
    end
  end
end
