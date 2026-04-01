defmodule UptrackWeb.OAuth.WellKnownTest do
  use UptrackWeb.ConnCase

  describe "GET /.well-known/oauth-authorization-server" do
    test "returns RFC 8414 metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-authorization-server")
      response = json_response(conn, 200)

      assert response["issuer"]
      assert response["token_endpoint"]
      assert response["authorization_endpoint"]
      assert response["grant_types_supported"] == ["authorization_code", "refresh_token"]
      assert response["response_types_supported"] == ["code"]
      assert response["code_challenge_methods_supported"] == ["S256"]
      assert is_list(response["scopes_supported"])
      assert "monitors:read" in response["scopes_supported"]
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    test "returns RFC 9728 metadata", %{conn: conn} do
      conn = get(conn, "/.well-known/oauth-protected-resource")
      response = json_response(conn, 200)

      assert response["resource"]
      assert is_list(response["authorization_servers"])
      assert response["bearer_methods_supported"] == ["header"]
      assert is_list(response["scopes_supported"])
    end
  end
end
