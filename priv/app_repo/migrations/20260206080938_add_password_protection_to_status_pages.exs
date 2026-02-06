defmodule Uptrack.AppRepo.Migrations.AddPasswordProtectionToStatusPages do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: "app") do
      add :password_protected, :boolean, default: false, null: false
      add :password_hash, :string
    end

    # Add index for faster lookup of password-protected pages
    create index(:status_pages, [:password_protected], prefix: "app")
  end
end
