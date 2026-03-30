defmodule Uptrack.AppRepo.Migrations.CreateSamlProviders do
  use Ecto.Migration

  def change do
    create table(:saml_providers, prefix: "app", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :organization_id, references(:organizations, type: :binary_id, prefix: "app", on_delete: :delete_all), null: false
      add :entity_id, :string, null: false
      add :sso_url, :string, null: false
      add :slo_url, :string
      add :certificate, :text, null: false
      add :metadata_xml, :text
      add :name_id_format, :string, default: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
      add :enforce, :boolean, default: false, null: false
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:saml_providers, [:organization_id], prefix: "app")
    create unique_index(:saml_providers, [:entity_id], prefix: "app")
  end
end
