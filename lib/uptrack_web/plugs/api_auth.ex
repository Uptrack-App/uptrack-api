defmodule UptrackWeb.Plugs.ApiAuth do
  @moduledoc """
  Plug for API authentication.

  Supports two authentication methods:
  1. Session-based (for same-origin requests from the frontend)
  2. Bearer token (for API access - future feature)

  Currently uses session authentication for the TanStack Start frontend.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Uptrack.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> fetch_current_user_from_session()
    |> require_authenticated_user()
  end

  defp fetch_current_user_from_session(conn) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Accounts.get_user!(user_id)
      assign(conn, :current_user, user)
    else
      conn
    end
  rescue
    Ecto.NoResultsError ->
      conn
  end

  defp require_authenticated_user(conn) do
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
