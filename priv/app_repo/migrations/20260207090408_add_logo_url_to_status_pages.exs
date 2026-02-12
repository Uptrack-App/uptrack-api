defmodule Uptrack.AppRepo.Migrations.AddLogoUrlToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add :logo_url, :string
    end
  end
end
