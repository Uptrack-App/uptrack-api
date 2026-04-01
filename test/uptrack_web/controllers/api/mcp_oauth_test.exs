defmodule UptrackWeb.MCPOAuthTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures
  import Uptrack.OAuthFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    client = oauth_client_fixture(org.id)
    {:ok, user: user, org: org, client: client}
  end

  describe "MCP with OAuth Bearer token" do
    test "authenticates with valid OAuth token", %{org: org, client: client} do
      token = oauth_token_fixture(client, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1})

      assert json_response(conn, 200)["result"] == %{}
    end

    test "rejects expired OAuth token", %{org: org, client: client} do
      token = expired_oauth_token_fixture(client, org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1})

      assert json_response(conn, 401)["error"]["code"] == -32_001
    end

    test "rejects missing auth", %{} do
      conn =
        build_conn()
        |> post("/api/mcp", %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1})

      assert json_response(conn, 401)["error"]["code"] == -32_001
    end
  end

  describe "MCP scope enforcement" do
    test "read scope allows read tool", %{org: org, client: client, user: user} do
      token = oauth_token_fixture(client, org.id, scope: "monitors:read")
      monitor_fixture(user_id: user.id, organization_id: org.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "id" => 1,
          "params" => %{"name" => "list_monitors", "arguments" => %{}}
        })

      response = json_response(conn, 200)
      assert response["result"]["isError"] == false
    end

    test "read scope blocks write tool", %{org: org, client: client} do
      token = oauth_token_fixture(client, org.id, scope: "monitors:read")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0",
          "method" => "tools/call",
          "id" => 1,
          "params" => %{"name" => "create_monitor", "arguments" => %{"url" => "https://example.com", "name" => "Test"}}
        })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32_003
      assert response["error"]["message"] =~ "monitors:write"
    end

    test "multiple scopes work together", %{org: org, client: client} do
      token = oauth_token_fixture(client, org.id, scope: "monitors:read analytics:read")

      # monitors:read should work
      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0", "method" => "tools/call", "id" => 1,
          "params" => %{"name" => "list_monitors", "arguments" => %{}}
        })

      assert json_response(conn1, 200)["result"]["isError"] == false

      # analytics:read should work
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0", "method" => "tools/call", "id" => 2,
          "params" => %{"name" => "get_dashboard_stats", "arguments" => %{}}
        })

      assert json_response(conn2, 200)["result"]["isError"] == false

      # incidents:read should be blocked (not in scope)
      conn3 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0", "method" => "tools/call", "id" => 3,
          "params" => %{"name" => "list_incidents", "arguments" => %{}}
        })

      assert json_response(conn3, 200)["error"]["code"] == -32_003
    end
  end

  describe "MCP organization isolation" do
    test "OAuth token only sees its own org's data", %{org: org, client: client, user: user} do
      # Create monitor in this org
      monitor_fixture(user_id: user.id, organization_id: org.id, name: "My Monitor")

      # Create monitor in another org
      {other_user, other_org} = user_with_org_fixture()
      monitor_fixture(user_id: other_user.id, organization_id: other_org.id, name: "Other Monitor")

      token = oauth_token_fixture(client, org.id, scope: "monitors:read")

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/mcp", %{
          "jsonrpc" => "2.0", "method" => "tools/call", "id" => 1,
          "params" => %{"name" => "list_monitors", "arguments" => %{}}
        })

      response = json_response(conn, 200)
      content = response["result"]["structuredContent"]
      names = Enum.map(content, & &1["name"])

      assert "My Monitor" in names
      refute "Other Monitor" in names
    end
  end

  describe "MCP backward compatibility" do
    test "session auth still works on /api/mcp", %{} do
      %{conn: conn} = setup_api_auth(build_conn())

      conn = post(conn, "/api/mcp", %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1})
      assert json_response(conn, 200)["result"] == %{}
    end

    test "session auth gets full access (no scope restriction)", %{} do
      %{conn: conn} = setup_api_auth(build_conn())

      # Should work even though no explicit scope — session gets :all
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0", "method" => "tools/call", "id" => 1,
        "params" => %{"name" => "list_monitors", "arguments" => %{}}
      })

      assert json_response(conn, 200)["result"]["isError"] == false
    end
  end
end
