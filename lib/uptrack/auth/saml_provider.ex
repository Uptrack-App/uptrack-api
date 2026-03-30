defmodule Uptrack.Auth.SamlProvider do
  @moduledoc """
  Schema for storing SAML IdP configuration per organization.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Uniq.UUID, version: 7, autogenerate: true}
  @foreign_key_type Uniq.UUID
  @schema_prefix "app"
  schema "saml_providers" do
    field :entity_id, :string
    field :sso_url, :string
    field :slo_url, :string
    field :certificate, :string
    field :metadata_xml, :string
    field :name_id_format, :string, default: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    field :enforce, :boolean, default: false
    field :is_active, :boolean, default: true

    belongs_to :organization, Uptrack.Organizations.Organization

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [
      :organization_id, :entity_id, :sso_url, :slo_url,
      :certificate, :metadata_xml, :name_id_format,
      :enforce, :is_active
    ])
    |> validate_required([:organization_id, :entity_id, :sso_url, :certificate])
    |> validate_format(:sso_url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> unique_constraint(:organization_id)
    |> unique_constraint(:entity_id)
  end
end
