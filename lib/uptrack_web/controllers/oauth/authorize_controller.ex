defmodule UptrackWeb.OAuth.AuthorizeController do
  @moduledoc """
  OAuth 2.0 authorization endpoint — consent screen for third-party apps.
  """

  @behaviour Boruta.Oauth.AuthorizeApplication

  use UptrackWeb, :controller

  def oauth_module, do: Application.get_env(:uptrack, :oauth_module, Boruta.Oauth)

  def authorize(conn, _params) do
    conn |> oauth_module().authorize(__MODULE__)
  end

  @impl true
  def authorize_success(conn, response) do
    redirect_uri = "#{response.redirect_uri}?code=#{response.code}&state=#{response.state}"

    conn
    |> redirect(external: redirect_uri)
  end

  @impl true
  def authorize_error(conn, error) do
    conn
    |> put_status(Map.get(error, :status, :bad_request))
    |> json(%{error: Map.get(error, :error), error_description: Map.get(error, :error_description)})
  end
end
