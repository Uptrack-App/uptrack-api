defmodule Uptrack.Auth.Saml do
  @moduledoc """
  SAML SSO context — manages SAML provider configuration and SSO login.

  Wraps Samly for per-organization IdP configuration stored in the database.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Auth.{SamlProvider, SamlResponse}
  alias Uptrack.Accounts
  alias Uptrack.Organizations

  require Logger

  # --- Provider CRUD ---

  def get_provider(organization_id) do
    AppRepo.get_by(SamlProvider, organization_id: organization_id)
  end

  def get_provider_by_entity_id(entity_id) do
    AppRepo.get_by(SamlProvider, entity_id: entity_id)
  end

  def configure(organization_id, attrs) do
    case get_provider(organization_id) do
      nil ->
        %SamlProvider{}
        |> SamlProvider.changeset(Map.put(attrs, :organization_id, organization_id))
        |> AppRepo.insert()

      existing ->
        existing
        |> SamlProvider.changeset(attrs)
        |> AppRepo.update()
    end
  end

  def delete_provider(organization_id) do
    case get_provider(organization_id) do
      nil -> {:error, :not_found}
      provider -> AppRepo.delete(provider)
    end
  end

  # --- SSO Login ---

  @doc """
  Handles a successful SAML assertion by finding or creating the user.

  Returns `{:ok, user}` or `{:error, reason}`.
  """
  def handle_sso_callback(%Samly.Assertion{} = assertion, provider) do
    attrs = SamlResponse.extract_attributes(assertion)

    if is_nil(attrs.email) do
      {:error, :no_email_in_assertion}
    else
      case Accounts.get_user_by_email(attrs.email) do
        nil ->
          # JIT provisioning — create user in the provider's org
          create_sso_user(attrs, provider)

        user ->
          # Existing user — verify they belong to the same org
          if user.organization_id == provider.organization_id do
            {:ok, user}
          else
            {:error, :user_org_mismatch}
          end
      end
    end
  end

  defp create_sso_user(attrs, provider) do
    Accounts.create_user_from_oauth(%{
      email: attrs.email,
      name: attrs.name || attrs.email,
      provider: "saml",
      provider_id: attrs.provider_id,
      organization_id: provider.organization_id
    })
  end

  # --- Enforcement ---

  @doc """
  Checks if SSO is enforced for an organization.
  Returns true if the org has an active SAML provider with enforce=true.
  """
  def sso_enforced?(organization_id) do
    from(p in SamlProvider,
      where: p.organization_id == ^organization_id and p.is_active == true and p.enforce == true
    )
    |> AppRepo.exists?()
  end

  @doc """
  Returns true if the org has SSO configured (active provider exists).
  """
  def sso_configured?(organization_id) do
    from(p in SamlProvider,
      where: p.organization_id == ^organization_id and p.is_active == true
    )
    |> AppRepo.exists?()
  end
end
