defmodule UptrackWeb.MCPControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "POST /api/mcp" do
    test "initialize returns server info", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "initialize",
        "id" => 1
      })

      response = json_response(conn, 200)
      assert response["result"]["serverInfo"]["name"] == "uptrack-mcp-server"
      assert response["result"]["protocolVersion"]
      assert response["result"]["capabilities"]["tools"]
    end

    test "tools/list returns available tools", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "tools/list",
        "id" => 2
      })

      response = json_response(conn, 200)
      tools = response["result"]["tools"]
      assert is_list(tools)
      assert length(tools) >= 10

      tool_names = Enum.map(tools, & &1["name"])
      assert "list_monitors" in tool_names
      assert "create_monitor" in tool_names
      assert "get_dashboard_stats" in tool_names
      assert "list_incidents" in tool_names
    end

    test "tools/call list_monitors works", %{conn: conn, user: user, org: org} do
      monitor_fixture(user_id: user.id, organization_id: org.id)

      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 3,
        "params" => %{"name" => "list_monitors", "arguments" => %{}}
      })

      response = json_response(conn, 200)
      assert response["result"]["isError"] == false

      content = response["result"]["structuredContent"]
      assert is_list(content)
      assert length(content) >= 1
    end

    test "tools/call get_dashboard_stats works", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 4,
        "params" => %{"name" => "get_dashboard_stats", "arguments" => %{}}
      })

      response = json_response(conn, 200)
      assert response["result"]["isError"] == false
    end

    test "tools/call list_incidents works", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 5,
        "params" => %{"name" => "list_incidents", "arguments" => %{}}
      })

      response = json_response(conn, 200)
      assert response["result"]["isError"] == false
    end

    test "tools/call unknown tool returns error", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 6,
        "params" => %{"name" => "nonexistent_tool", "arguments" => %{}}
      })

      response = json_response(conn, 200)
      assert response["result"]["isError"] == true
    end

    test "ping works", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "ping",
        "id" => 7
      })

      response = json_response(conn, 200)
      assert response["result"] == %{}
    end

    test "unknown method returns error", %{conn: conn} do
      conn = post(conn, "/api/mcp", %{
        "jsonrpc" => "2.0",
        "method" => "unknown/method",
        "id" => 8
      })

      response = json_response(conn, 200)
      assert response["error"]["code"] == -32_601
    end

    test "requires authentication", %{} do
      conn = build_conn()
      conn = post(conn, "/api/mcp", %{"jsonrpc" => "2.0", "method" => "ping", "id" => 1})
      assert conn.status in [401, 302]
    end
  end
end
