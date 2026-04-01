defmodule UptrackWeb.OAuth.ProtectedResourceController do
  @moduledoc """
  OAuth 2.0 Protected Resource Metadata per RFC 9728.

  Endpoint: `GET /.well-known/oauth-protected-resource`
  """

  use UptrackWeb, :controller

  alias Uptrack.OAuth.Scopes

  def index(conn, _params) do
    resource_uri = resource_uri()

    conn
    |> put_resp_content_type("application/json")
    |> json(%{
      resource: resource_uri,
      authorization_servers: [resource_uri],
      scopes_supported: Scopes.all_scopes(),
      bearer_methods_supported: ["header"]
    })
  end

  defp resource_uri do
    host = Application.get_env(:uptrack, UptrackWeb.Endpoint)[:url][:host] || "api.uptrack.app"
    "https://#{host}"
  end
end
