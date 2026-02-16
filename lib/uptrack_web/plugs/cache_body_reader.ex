defmodule UptrackWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Custom body reader that caches the raw request body.

  Used for webhook signature verification where we need the exact bytes
  that were sent (JSON re-serialization changes whitespace/ordering).

  ## Usage in router

      plug Plug.Parsers,
        parsers: [:json],
        body_reader: {UptrackWeb.Plugs.CacheBodyReader, :read_body, []},
        json_decoder: Jason
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.put_private(conn, :raw_body, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
