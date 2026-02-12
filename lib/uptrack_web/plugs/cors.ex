defmodule UptrackWeb.Plugs.CORS do
  @moduledoc """
  CORS plug for cross-origin API requests from the TanStack frontend.

  Allowed origins are configured via the :cors_origins application env key.
  In dev, defaults to ["http://localhost:3000"].
  In prod, reads from the CORS_ORIGINS environment variable (comma-separated).
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn =
      if origin && allowed_origin?(origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "authorization, content-type")
        |> put_resp_header("access-control-allow-credentials", "true")
        |> put_resp_header("access-control-max-age", "3600")
      else
        conn
      end

    if conn.method == "OPTIONS" do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end

  defp allowed_origin?(origin) do
    allowed = Application.get_env(:uptrack, :cors_origins, ["http://localhost:3000"])
    origin in allowed or "*" in allowed
  end
end
