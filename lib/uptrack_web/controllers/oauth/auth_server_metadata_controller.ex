defmodule UptrackWeb.OAuth.AuthServerMetadataController do
  @moduledoc """
  OAuth 2.0 Authorization Server Metadata per RFC 8414.

  Endpoint: `GET /.well-known/oauth-authorization-server`
  """

  use UptrackWeb, :controller

  alias Uptrack.OAuth.Scopes

  def index(conn, _params) do
    issuer = issuer_uri()

    conn
    |> put_resp_content_type("application/json")
    |> json(%{
      issuer: issuer,
      authorization_endpoint: "#{issuer}/oauth/authorize",
      token_endpoint: "#{issuer}/oauth/token",
      revocation_endpoint: "#{issuer}/oauth/revoke",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["client_secret_post", "client_secret_basic", "none"],
      scopes_supported: Scopes.all_scopes(),
      registration_endpoint: "#{issuer}/oauth/register",
      client_id_metadata_document_supported: true
    })
  end

  defp issuer_uri do
    host = Application.get_env(:uptrack, UptrackWeb.Endpoint)[:url][:host] || "api.uptrack.app"
    "https://#{host}"
  end
end
