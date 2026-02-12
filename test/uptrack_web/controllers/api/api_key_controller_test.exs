defmodule UptrackWeb.Api.ApiKeyControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Accounts.ApiKeys

  setup %{conn: conn} do
    %{conn: conn, user: user, org: org} = setup_api_auth(conn)
    {:ok, conn: conn, user: user, org: org}
  end

  describe "GET /api/api-keys" do
    test "lists API keys for the organization", %{conn: conn, user: user, org: org} do
      {:ok, _} =
        ApiKeys.create_api_key(%{name: "My Key", organization_id: org.id, created_by_id: user.id})

      conn = get(conn, ~p"/api/api-keys")
      response = json_response(conn, 200)

      assert length(response["api_keys"]) == 1
      assert hd(response["api_keys"])["name"] == "My Key"
      # raw_key should NOT be in listing
      refute Map.has_key?(hd(response["api_keys"]), "raw_key")
    end
  end

  describe "POST /api/api-keys" do
    test "creates a new API key and returns raw key once", %{conn: conn} do
      conn = post(conn, ~p"/api/api-keys", %{"name" => "Production Key"})
      response = json_response(conn, 201)

      assert response["api_key"]["name"] == "Production Key"
      assert String.starts_with?(response["raw_key"], "utk_")
      assert response["message"] =~ "Store this key"
    end

    test "creates key with custom scopes", %{conn: conn} do
      conn =
        post(conn, ~p"/api/api-keys", %{
          "name" => "Read-only Key",
          "scopes" => ["read"]
        })

      response = json_response(conn, 201)
      assert response["api_key"]["scopes"] == ["read"]
    end
  end

  describe "DELETE /api/api-keys/:id" do
    test "deletes an API key", %{conn: conn, user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{name: "Delete Me", organization_id: org.id, created_by_id: user.id})

      conn = delete(conn, ~p"/api/api-keys/#{api_key.id}")
      response = json_response(conn, 200)

      assert response["success"] == true
    end

    test "returns 404 for non-existent key", %{conn: conn} do
      conn = delete(conn, ~p"/api/api-keys/00000000-0000-0000-0000-000000000000")
      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "POST /api/api-keys/:id/revoke" do
    test "revokes an API key", %{conn: conn, user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{name: "Revoke Me", organization_id: org.id, created_by_id: user.id})

      conn = post(conn, ~p"/api/api-keys/#{api_key.id}/revoke")
      response = json_response(conn, 200)

      assert response["api_key"]["is_active"] == false
      assert response["message"] =~ "revoked"
    end
  end

  describe "Bearer token authentication" do
    test "authenticates with valid API key", %{conn: _conn, user: user, org: org} do
      {:ok, api_key} =
        ApiKeys.create_api_key(%{
          name: "Bearer Test",
          organization_id: org.id,
          created_by_id: user.id
        })

      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("authorization", "Bearer #{api_key.raw_key}")
        |> get(~p"/api/analytics/dashboard")

      assert json_response(conn, 200)
    end

    test "rejects invalid Bearer token" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("authorization", "Bearer utk_invalid_token")
        |> get(~p"/api/analytics/dashboard")

      assert json_response(conn, 401)
    end
  end
end
