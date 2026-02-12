defmodule UptrackWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for API authentication.

  Supports two authentication methods:
  1. Bearer token - API key in `Authorization: Bearer utk_...` header
  2. Session-based - for same-origin requests from the frontend

  Bearer token auth is tried first. If no Bearer token is present,
  falls back to session-based authentication.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Uptrack.{Accounts, Organizations}
  alias Uptrack.Accounts.ApiKeys

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> authenticate()
    |> fetch_current_organization()
    |> require_authenticated()
  end

  defp authenticate(conn) do
    case get_bearer_token(conn) do
      {:ok, token} -> authenticate_by_token(conn, token)
      :error -> authenticate_by_session(conn)
    end
  end

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> :error
    end
  end

  defp authenticate_by_token(conn, token) do
    case ApiKeys.authenticate_by_key(token) do
      {:ok, api_key} ->
        # Load the user who created the key for assign compatibility
        user = Accounts.get_user!(api_key.created_by_id)

        conn
        |> assign(:current_user, user)
        |> assign(:current_api_key, api_key)
        |> assign(:auth_method, :api_key)

      {:error, _reason} ->
        conn
    end
  rescue
    Ecto.NoResultsError -> conn
  end

  defp authenticate_by_session(conn) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Accounts.get_user!(user_id)

      conn
      |> assign(:current_user, user)
      |> assign(:auth_method, :session)
    else
      conn
    end
  rescue
    Ecto.NoResultsError -> conn
  end

  defp fetch_current_organization(%{assigns: %{current_user: user}} = conn) when not is_nil(user) do
    organization = Organizations.get_organization!(user.organization_id)
    assign(conn, :current_organization, organization)
  rescue
    Ecto.NoResultsError -> conn
  end

  defp fetch_current_organization(conn), do: conn

  defp require_authenticated(conn) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> put_view(json: UptrackWeb.Api.ErrorJSON)
      |> render(:error, message: "Authentication required")
      |> halt()
    end
  end
end
