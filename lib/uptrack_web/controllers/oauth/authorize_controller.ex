defmodule UptrackWeb.OAuth.AuthorizeController do
  @moduledoc """
  OAuth 2.0 authorization endpoint.

  Handles the consent screen for third-party apps requesting access
  to a user's Uptrack organization data.
  """

  @behaviour Boruta.Oauth.AuthorizeApplication

  use UptrackWeb, :controller

  alias Boruta.Oauth.AuthorizeResponse
  alias Boruta.Oauth.Error

  def oauth_module, do: Application.get_env(:uptrack, :oauth_module, Boruta.Oauth)

  @doc "GET /oauth/authorize — renders consent screen or redirects if already authorized."
  def authorize(conn, _params) do
    conn |> oauth_module().authorize(__MODULE__)
  end

  @impl true
  def authorize_success(conn, %AuthorizeResponse{} = response) do
    redirect_uri = "#{response.redirect_uri}?code=#{response.code}&state=#{response.state}"

    conn
    |> redirect(external: redirect_uri)
  end

  @impl true
  def authorize_error(conn, %Error{status: status, error: error, error_description: error_description}) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: error_description})
  end
end
