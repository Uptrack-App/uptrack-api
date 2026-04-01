defmodule UptrackWeb.OAuth.TokenController do
  @moduledoc """
  OAuth 2.0 token endpoint with RFC 8707 Resource Indicators support.
  """

  @behaviour Boruta.Oauth.TokenApplication

  use UptrackWeb, :controller

  alias Uptrack.OAuth.{ResourceIndicators, Tokens}

  def oauth_module, do: Application.get_env(:uptrack, :oauth_module, Boruta.Oauth)

  def token(%Plug.Conn{body_params: body_params} = conn, _params) do
    resource = Map.get(body_params, "resource")

    if ResourceIndicators.valid_resource?(resource) do
      normalized = ResourceIndicators.format_resource(resource)

      conn
      |> Plug.Conn.assign(:oauth_resource, normalized)
      |> oauth_module().token(__MODULE__)
    else
      error = ResourceIndicators.invalid_target_error()

      conn
      |> put_status(:bad_request)
      |> json(%{error: error.error, error_description: error.error_description})
    end
  end

  @impl true
  def token_success(conn, response) do
    resource = conn.assigns[:oauth_resource]
    access_token = Map.get(response, :access_token)

    # RFC 8707: Store resource binding
    if access_token && resource do
      Tokens.set_token_resource(access_token, resource)
    end

    # Store org_id in sub claim from client metadata
    if access_token do
      store_org_sub(access_token, response)
    end

    conn
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("cache-control", "no-store")
    |> json(%{
      access_token: access_token,
      token_type: Map.get(response, :token_type),
      expires_in: Map.get(response, :expires_in),
      refresh_token: Map.get(response, :refresh_token),
      scope: Map.get(response, :scope)
    })
  end

  @impl true
  def token_error(conn, error) do
    conn
    |> put_status(Map.get(error, :status, :bad_request))
    |> json(%{error: Map.get(error, :error), error_description: Map.get(error, :error_description)})
  end

  defp store_org_sub(access_token, response) do
    client_id = Map.get(response, :client_id)

    case Uptrack.OAuth.get_client(client_id) do
      {:ok, client} ->
        org_id = get_in(client.metadata, ["organization_id"])
        if org_id, do: Tokens.set_token_sub(access_token, "org:#{org_id}")

      _ ->
        :ok
    end
  end
end
