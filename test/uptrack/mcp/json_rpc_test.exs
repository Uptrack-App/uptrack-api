defmodule Uptrack.MCP.JsonRpcTest do
  use ExUnit.Case, async: true

  alias Uptrack.MCP.JsonRpc

  describe "success_response/2" do
    test "returns valid JSON-RPC response" do
      response = JsonRpc.success_response(1, %{"tools" => []})

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"] == %{"tools" => []}
    end
  end

  describe "tool_response/2" do
    test "wraps ok result" do
      response = JsonRpc.tool_response(1, {:ok, %{status: "up"}})

      assert response["result"]["isError"] == false
      assert response["result"]["structuredContent"] == %{status: "up"}
      assert [%{"type" => "text", "text" => text}] = response["result"]["content"]
      assert Jason.decode!(text) == %{"status" => "up"}
    end

    test "wraps error result" do
      response = JsonRpc.tool_response(1, {:error, "Monitor not found"})

      assert response["result"]["isError"] == true
      assert [%{"type" => "text", "text" => "Monitor not found"}] = response["result"]["content"]
    end
  end

  describe "error_response/3" do
    test "returns error with code and message" do
      response = JsonRpc.error_response(1, -32_601, "Method not found")

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] == "Method not found"
    end

    test "includes data when provided" do
      response = JsonRpc.error_response(1, -32_602, "Invalid params", "extra info")

      assert response["error"]["data"] == "extra info"
    end
  end

  describe "define_tool/4" do
    test "creates tool definition" do
      tool = JsonRpc.define_tool("test_tool", "A test tool", %{
        "name" => JsonRpc.prop("string", "The name")
      }, ["name"])

      assert tool["name"] == "test_tool"
      assert tool["description"] == "A test tool"
      assert tool["inputSchema"]["type"] == "object"
      assert tool["inputSchema"]["required"] == ["name"]
      assert tool["inputSchema"]["properties"]["name"]["type"] == "string"
    end

    test "omits required when empty" do
      tool = JsonRpc.define_tool("no_req", "No required", %{})
      refute Map.has_key?(tool["inputSchema"], "required")
    end
  end

  describe "prop/2" do
    test "creates property definition" do
      prop = JsonRpc.prop("string", "A description")
      assert prop == %{"type" => "string", "description" => "A description"}
    end
  end
end
