defmodule Uptrack.AppRepo.Migrations.AddCustomDomainVerification do
  use Ecto.Migration

  def change do
    alter table(:status_pages, prefix: :app) do
      # Domain verification status
      add :domain_verified, :boolean, default: false
      add :domain_verification_token, :string
      add :domain_verified_at, :utc_datetime

      # SSL certificate status
      add :ssl_status, :string, default: "pending"
      add :ssl_expires_at, :utc_datetime
      add :ssl_issued_at, :utc_datetime
    end

    # Index for looking up status pages by custom domain
    create index(:status_pages, [:custom_domain], prefix: :app, where: "custom_domain IS NOT NULL")
  end
end
