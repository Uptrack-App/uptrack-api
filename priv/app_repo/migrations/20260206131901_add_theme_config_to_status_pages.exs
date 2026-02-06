defmodule Uptrack.AppRepo.Migrations.AddThemeConfigToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add :theme_config, :map, default: %{}
    end
  end
end
