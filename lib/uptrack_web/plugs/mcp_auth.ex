defmodule UptrackWeb.Plugs.MCPAuth do
  @moduledoc """
  Dual-mode authentication for the MCP endpoint.

  Priority order:
  1. OAuth Bearer token → Boruta token lookup → org from `sub` claim
  2. Bearer token as API key → API key table lookup (backward compatible)
  3. Session auth → existing session cookie (backward compatible)

  Assigns: current_organization, auth_method, oauth_scopes
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Boruta.Ecto.AccessTokens
  alias Uptrack.{Accounts, Organizations}
  alias Uptrack.Accounts.ApiKeys
  alias Uptrack.OAuth.Tokens

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_bearer_token(conn) do
      {:ok, token} ->
        conn
        |> try_oauth_token(token)
        |> try_api_key(token)
        |> require_auth()

      :error ->
        conn
        |> try_session_auth()
        |> require_auth()
    end
  end

  # --- Token extraction ---

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end

  # --- OAuth token path ---

  defp try_oauth_token(%{assigns: %{current_organization: _}} = conn, _token), do: conn

  defp try_oauth_token(conn, token) do
    case AccessTokens.get_by(value: token) do
      nil ->
        conn

      oauth_token ->
        if token_valid?(oauth_token) do
          authenticate_oauth(conn, token, oauth_token)
        else
          conn
        end
    end
  end

  defp token_valid?(token) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    !token.revoked_at && token.expires_at > now
  end

  defp authenticate_oauth(conn, token_value, oauth_token) do
    sub = Tokens.get_token_sub(token_value)

    case Tokens.extract_org_id(sub) do
      {:ok, org_id} ->
        org = Organizations.get_organization!(org_id)
        scopes = parse_scopes(oauth_token.scope)

        conn
        |> assign(:current_organization, org)
        |> assign(:auth_method, :oauth)
        |> assign(:oauth_scopes, scopes)

      _ ->
        Logger.warning("MCP OAuth: invalid sub claim: #{inspect(sub)}")
        conn
    end
  rescue
    Ecto.NoResultsError ->
      Logger.warning("MCP OAuth: organization not found for sub")
      conn
  end

  defp parse_scopes(nil), do: []
  defp parse_scopes(scope) when is_binary(scope), do: String.split(scope, " ")

  # --- API key path (backward compatible) ---

  defp try_api_key(%{assigns: %{current_organization: _}} = conn, _token), do: conn

  defp try_api_key(conn, token) do
    case ApiKeys.authenticate_by_key(token) do
      {:ok, api_key} ->
        user = Accounts.get_user!(api_key.created_by_id)
        org = Organizations.get_organization!(user.organization_id)

        conn
        |> assign(:current_user, user)
        |> assign(:current_organization, org)
        |> assign(:current_api_key, api_key)
        |> assign(:auth_method, :api_key)
        |> assign(:oauth_scopes, :all)

      {:error, _} ->
        conn
    end
  rescue
    Ecto.NoResultsError -> conn
  end

  # --- Session path (backward compatible) ---

  defp try_session_auth(conn) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Accounts.get_user!(user_id)
      org = Organizations.get_organization!(user.organization_id)

      conn
      |> assign(:current_user, user)
      |> assign(:current_organization, org)
      |> assign(:auth_method, :session)
      |> assign(:oauth_scopes, :all)
    else
      conn
    end
  rescue
    Ecto.NoResultsError -> conn
  end

  # --- Require auth ---

  defp require_auth(%{assigns: %{current_organization: _}} = conn), do: conn

  defp require_auth(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{jsonrpc: "2.0", id: nil, error: %{code: -32_001, message: "Authentication required"}})
    |> halt()
  end
end
