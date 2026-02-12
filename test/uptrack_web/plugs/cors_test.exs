defmodule UptrackWeb.Plugs.CORSTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias UptrackWeb.Plugs.CORS

  setup do
    Application.put_env(:uptrack, :cors_origins, ["http://localhost:3000"])
    on_exit(fn -> Application.put_env(:uptrack, :cors_origins, ["http://localhost:3000"]) end)
  end

  describe "CORS headers" do
    test "adds CORS headers for allowed origin" do
      conn =
        conn(:get, "/api/monitors")
        |> put_req_header("origin", "http://localhost:3000")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
      assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]
      refute conn.halted
    end

    test "does not add CORS headers for disallowed origin" do
      conn =
        conn(:get, "/api/monitors")
        |> put_req_header("origin", "http://evil.com")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == []
      refute conn.halted
    end

    test "does not add CORS headers when no origin header" do
      conn =
        conn(:get, "/api/monitors")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == []
      refute conn.halted
    end

    test "handles OPTIONS preflight and halts" do
      conn =
        conn(:options, "/api/monitors")
        |> put_req_header("origin", "http://localhost:3000")
        |> CORS.call(CORS.init([]))

      assert conn.status == 204
      assert conn.halted
      assert get_resp_header(conn, "access-control-allow-methods") ==
               ["GET, POST, PUT, PATCH, DELETE, OPTIONS"]
      assert get_resp_header(conn, "access-control-allow-headers") ==
               ["authorization, content-type"]
      assert get_resp_header(conn, "access-control-max-age") == ["3600"]
    end

    test "OPTIONS from disallowed origin returns 204 but no CORS headers" do
      conn =
        conn(:options, "/api/monitors")
        |> put_req_header("origin", "http://evil.com")
        |> CORS.call(CORS.init([]))

      assert conn.status == 204
      assert conn.halted
      assert get_resp_header(conn, "access-control-allow-origin") == []
    end

    test "supports wildcard origin" do
      Application.put_env(:uptrack, :cors_origins, ["*"])

      conn =
        conn(:get, "/api/monitors")
        |> put_req_header("origin", "http://anything.com")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == ["http://anything.com"]
    end

    test "supports multiple configured origins" do
      Application.put_env(:uptrack, :cors_origins, ["http://localhost:3000", "https://app.uptrack.dev"])

      conn1 =
        conn(:get, "/api/monitors")
        |> put_req_header("origin", "https://app.uptrack.dev")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn1, "access-control-allow-origin") == ["https://app.uptrack.dev"]

      conn2 =
        conn(:get, "/api/monitors")
        |> put_req_header("origin", "http://other.com")
        |> CORS.call(CORS.init([]))

      assert get_resp_header(conn2, "access-control-allow-origin") == []
    end
  end
end
