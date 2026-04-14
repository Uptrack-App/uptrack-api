defmodule UptrackWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that restricts access to platform admin users only.

  Requires ApiAuth to have already run. Checks `current_user.is_admin == true`
  and returns 403 otherwise.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && user.is_admin do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(json: UptrackWeb.Api.ErrorJSON)
      |> render(:error, message: "forbidden")
      |> halt()
    end
  end
end
