defmodule Uptrack.AppRepo.Migrations.AddIsAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users, prefix: :app) do
      add :is_admin, :boolean, null: false, default: false
    end
  end
end
