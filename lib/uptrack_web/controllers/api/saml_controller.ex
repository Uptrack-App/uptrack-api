defmodule UptrackWeb.Api.SamlController do
  use UptrackWeb, :controller

  alias Uptrack.Auth.Saml
  alias Uptrack.Billing

  require Logger

  @doc """
  GET /api/auth/sso/config — returns SSO configuration for the org.
  """
  def show(conn, _params) do
    org = conn.assigns.current_organization
    provider = Saml.get_provider(org.id)

    json(conn, %{
      data: if(provider, do: %{
        entity_id: provider.entity_id,
        sso_url: provider.sso_url,
        slo_url: provider.slo_url,
        name_id_format: provider.name_id_format,
        enforce: provider.enforce,
        is_active: provider.is_active,
        has_certificate: provider.certificate != nil
      })
    })
  end

  @doc """
  POST /api/auth/sso/config — configure SSO for the org (Business plan only).
  """
  def configure(conn, params) do
    org = conn.assigns.current_organization

    if Billing.can_use_feature?(org, :sso) do
      attrs = %{
        entity_id: params["entity_id"],
        sso_url: params["sso_url"],
        slo_url: params["slo_url"],
        certificate: params["certificate"],
        metadata_xml: params["metadata_xml"],
        name_id_format: params["name_id_format"],
        enforce: params["enforce"] || false
      }

      case Saml.configure(org.id, attrs) do
        {:ok, _provider} ->
          json(conn, %{ok: true, message: "SSO configured successfully."})

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      conn
      |> put_status(402)
      |> json(%{error: %{message: "SSO/SAML is available on the Business plan."}})
    end
  end

  @doc """
  DELETE /api/auth/sso/config — remove SSO configuration.
  """
  def delete(conn, _params) do
    org = conn.assigns.current_organization

    case Saml.delete_provider(org.id) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, :not_found} -> json(conn, %{ok: true})
    end
  end

  @doc """
  GET /api/auth/sso/status — check if SSO is configured for current org.
  """
  def status(conn, _params) do
    org = conn.assigns.current_organization

    json(conn, %{
      configured: Saml.sso_configured?(org.id),
      enforced: Saml.sso_enforced?(org.id)
    })
  end
end
