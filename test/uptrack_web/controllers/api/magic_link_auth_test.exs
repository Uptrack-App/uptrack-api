defmodule UptrackWeb.MagicLinkAuthTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Auth.MagicLink

  @moduletag :capture_log

  describe "POST /api/auth/magic-link" do
    test "returns ok for any email", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link", %{"email" => "new@example.com"})
      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "returns ok for existing user email", %{conn: conn} do
      {user, _org} = user_with_org_fixture()

      conn = post(conn, "/api/auth/magic-link", %{"email" => user.email})
      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "returns 422 without email", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link", %{})
      assert json_response(conn, 422)
    end
  end

  describe "POST /api/auth/magic-link/verify" do
    test "logs in existing user with valid token", %{conn: conn} do
      {user, _org} = user_with_org_fixture()
      {raw, hashed} = MagicLink.generate_token()
      {:ok, _} = Uptrack.Accounts.store_magic_token(user.email, hashed)

      conn = post(conn, "/api/auth/magic-link/verify", %{"email" => user.email, "token" => raw})
      response = json_response(conn, 200)

      assert response["user"]["email"] == user.email
      assert response["organization"]
    end

    test "creates new user with valid token for unknown email", %{conn: conn} do
      email = "brandnew-#{System.unique_integer([:positive])}@example.com"
      {raw, hashed} = MagicLink.generate_token()
      {:ok, _} = Uptrack.Accounts.store_magic_token(email, hashed)

      conn = post(conn, "/api/auth/magic-link/verify", %{"email" => email, "token" => raw})
      response = json_response(conn, 200)

      assert response["user"]["email"] == String.downcase(email)
      assert response["organization"]
    end

    test "rejects invalid token", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link/verify", %{"email" => "x@x.com", "token" => "bad-token"})
      assert json_response(conn, 401)["error"] == "Invalid token"
    end

    test "rejects expired token", %{conn: conn} do
      email = "expired@example.com"
      {raw, hashed} = MagicLink.generate_token()

      # Store with already-expired time
      {:ok, token} = Uptrack.Accounts.store_magic_token(email, hashed)
      expired_at = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      Ecto.Changeset.change(token, %{expires_at: expired_at}) |> Uptrack.AppRepo.update!()

      conn = post(conn, "/api/auth/magic-link/verify", %{"email" => email, "token" => raw})
      assert json_response(conn, 401)["error"] == "Token expired"
    end

    test "rejects already-used token", %{conn: conn} do
      email = "used@example.com"
      {raw, hashed} = MagicLink.generate_token()
      {:ok, _} = Uptrack.Accounts.store_magic_token(email, hashed)

      # First use — should work
      conn1 = post(build_conn(), "/api/auth/magic-link/verify", %{"email" => email, "token" => raw})
      assert json_response(conn1, 200)["user"]

      # Second use — should fail (token consumed, lookup returns nil → "Invalid token")
      conn2 = post(conn, "/api/auth/magic-link/verify", %{"email" => email, "token" => raw})
      assert json_response(conn2, 401)["error"] == "Invalid token"
    end

    test "returns 422 without email or token", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link/verify", %{})
      assert json_response(conn, 422)
    end
  end
end
