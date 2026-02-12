defmodule Uptrack.AppRepo.Migrations.FixStatusPageMonitorsColumns do
  use Ecto.Migration

  def change do
    alter table(:status_page_monitors, prefix: :app) do
      add :display_name, :string
    end

    rename table(:status_page_monitors, prefix: :app), :display_order, to: :sort_order
  end
end
