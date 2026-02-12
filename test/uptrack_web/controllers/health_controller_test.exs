defmodule UptrackWeb.HealthControllerTest do
  use UptrackWeb.ConnCase

  describe "GET /healthz" do
    test "returns alive status", %{conn: conn} do
      conn = get(conn, ~p"/healthz")
      response = json_response(conn, 200)

      assert response["status"] == "alive"
      assert is_binary(response["version"])
      assert is_binary(response["timestamp"])
      assert is_binary(response["node_region"])
    end

    test "includes ISO 8601 timestamp", %{conn: conn} do
      conn = get(conn, ~p"/healthz")
      response = json_response(conn, 200)

      # Verify it's a valid ISO 8601 datetime
      assert {:ok, _dt, _offset} = DateTime.from_iso8601(response["timestamp"])
    end
  end

  describe "GET /ready" do
    test "returns readiness check with dependency statuses", %{conn: conn} do
      conn = get(conn, ~p"/ready")
      response = json_response(conn, 200)

      assert response["status"] in ["ready", "not_ready"]
      assert is_map(response["checks"])
      assert is_binary(response["version"])
      assert is_binary(response["timestamp"])
      assert is_binary(response["node_region"])
      assert is_binary(response["node_name"])
    end

    test "checks database connectivity", %{conn: conn} do
      conn = get(conn, ~p"/ready")
      response = json_response(conn, 200)

      # In test env with sandbox, the DB should be reachable
      assert response["checks"]["database"] == "ok"
    end

    test "checks oban connectivity", %{conn: conn} do
      conn = get(conn, ~p"/ready")
      response = json_response(conn, 200)

      assert response["checks"]["oban"] == "ok"
    end
  end
end
