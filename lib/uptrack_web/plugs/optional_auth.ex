defmodule UptrackWeb.Plugs.OptionalAuth do
  @moduledoc """
  Optionally loads the current user from session if present.
  Does NOT require authentication — conn proceeds either way.
  """
  import Plug.Conn

  alias Uptrack.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Accounts.get_user!(user_id)
      assign(conn, :current_user, user)
    else
      conn
    end
  rescue
    Ecto.NoResultsError -> conn
  end
end
