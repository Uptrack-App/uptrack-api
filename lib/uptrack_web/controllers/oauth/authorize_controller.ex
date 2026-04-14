defmodule UptrackWeb.OAuth.AuthorizeController do
  @moduledoc """
  OAuth 2.0 authorization endpoint.

  Flow:
  1. Resolve client_id (metadata doc or Boruta DB lookup)
  2. If user not logged in → show OAuth login page
  3. If user logged in → show consent screen
  4. On user approval → delegate to Boruta for auth code
  5. On user denial → redirect with error=access_denied
  """

  @behaviour Boruta.Oauth.AuthorizeApplication

  use UptrackWeb, :controller

  # OAuth consent pages are self-contained HTML — disable root layout
  plug :put_root_layout, false
  plug :put_layout, false

  alias Boruta.Oauth.AuthorizationSuccess
  alias Uptrack.Accounts
  alias Uptrack.OAuth

  require Logger

  def oauth_module, do: Application.get_env(:uptrack, :oauth_module, Boruta.Oauth)

  # --- GET /oauth/authorize ---

  def authorize(conn, params) do
    case get_session(conn, :user_id) do
      nil ->
        # Not logged in: save params in session, show login page
        conn
        |> put_session(:pending_oauth_params, params)
        |> render_login_page(params)

      user_id ->
        handle_logged_in(conn, user_id, params)
    end
  end

  # --- POST /oauth/authorize (approve) ---

  def approve(conn, params) do
    user_id = get_session(conn, :user_id)

    if is_nil(user_id) do
      conn
      |> put_session(:pending_oauth_params, params)
      |> render_login_page(params)
    else
      conn
      |> assign(:current_user_id, user_id)
      |> oauth_module().authorize(__MODULE__)
    end
  end

  # --- POST /oauth/authorize (deny) ---

  def deny(conn, %{"redirect_uri" => redirect_uri} = params) do
    state = Map.get(params, "state", "")

    error_uri =
      if state != "",
        do: "#{redirect_uri}?error=access_denied&state=#{URI.encode(state)}",
        else: "#{redirect_uri}?error=access_denied"

    redirect(conn, external: error_uri)
  end

  def deny(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "access_denied"})
  end

  # --- Boruta callbacks ---

  @impl true
  def authorize_success(conn, %AuthorizationSuccess{} = response) do
    state = response.state || ""

    redirect_uri =
      if state != "",
        do: "#{response.redirect_uri}?code=#{response.code}&state=#{state}",
        else: "#{response.redirect_uri}?code=#{response.code}"

    conn |> redirect(external: redirect_uri)
  end

  @impl true
  def authorize_error(conn, error) do
    conn
    |> put_status(Map.get(error, :status, :bad_request))
    |> json(%{error: Map.get(error, :error), error_description: Map.get(error, :error_description)})
  end

  # --- Private ---

  defp handle_logged_in(conn, user_id, params) do
    client_id = Map.get(params, "client_id")

    with {:ok, user} <- safe_get_user(user_id),
         {:ok, client} <- OAuth.resolve_client(client_id),
         :ok <- validate_redirect_uri(client, params) do
      requested_scopes = parse_scopes(Map.get(params, "scope", ""))
      human_scopes = Enum.map(requested_scopes, &scope_label/1)

      conn
      |> put_view(UptrackWeb.OAuth.AuthorizeHTML)
      |> render(:authorize,
        client_name: client.name,
        scopes: human_scopes,
        params: params,
        user_email: user.email
      )
    else
      {:error, :invalid_redirect_uri} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_redirect_uri"})

      {:error, :client_not_found} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_client", error_description: "Unknown client_id"})

      {:error, :invalid_client} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_client", error_description: "Could not fetch client metadata"})

      {:error, reason} ->
        Logger.warning("OAuth authorize error: #{inspect(reason)}")
        conn |> put_status(:bad_request) |> json(%{error: "invalid_request"})
    end
  end

  defp safe_get_user(user_id) do
    {:ok, Accounts.get_user!(user_id)}
  rescue
    Ecto.NoResultsError -> {:error, :user_not_found}
  end

  defp validate_redirect_uri(%{redirect_uris: uris}, %{"redirect_uri" => requested_uri}) do
    if requested_uri in uris or uris == [],
      do: :ok,
      else: {:error, :invalid_redirect_uri}
  end

  defp validate_redirect_uri(_client, _params), do: :ok

  defp render_login_page(conn, params) do
    client_id = Map.get(params, "client_id", "")

    client_name =
      case OAuth.resolve_client(client_id) do
        {:ok, client} -> client.name
        _ -> "an application"
      end

    conn
    |> put_view(UptrackWeb.OAuth.AuthorizeHTML)
    |> render(:login,
      client_name: client_name,
      params: params
    )
  end

  defp parse_scopes(nil), do: []
  defp parse_scopes(scope) when is_binary(scope), do: String.split(scope, " ", trim: true)

  defp scope_label("monitors:read"), do: "View your monitors"
  defp scope_label("monitors:write"), do: "Create and manage monitors"
  defp scope_label("incidents:read"), do: "View incidents"
  defp scope_label("incidents:write"), do: "Acknowledge incidents"
  defp scope_label("status_pages:read"), do: "View status pages"
  defp scope_label("alerts:read"), do: "View alert channels"
  defp scope_label("alerts:write"), do: "Create alert channels"
  defp scope_label("analytics:read"), do: "View analytics"
  defp scope_label(scope), do: scope
end
