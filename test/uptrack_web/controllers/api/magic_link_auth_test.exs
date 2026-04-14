defmodule UptrackWeb.MagicLinkAuthTest do
  use UptrackWeb.ConnCase

  import Uptrack.AccountsFixtures

  alias Uptrack.Auth.MagicLink

  @moduletag :capture_log

  describe "POST /api/auth/magic-link" do
    test "returns ok for any email", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link", %{"email" => "new@example.com"})
      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "returns ok for existing user email", %{conn: conn} do
      {:ok, org} =
        Uptrack.Organizations.create_organization(%{
          name: "Test Organization",
          slug: "test-org-#{Ecto.UUID.generate()}"
        })

      {:ok, user} =
        Uptrack.Accounts.create_user(%{
          email: "user-#{Ecto.UUID.generate()}@example.com",
          name: "Test User",
          password: "secure_password_123",
          organization_id: org.id
        })

      conn = post(conn, "/api/auth/magic-link", %{"email" => user.email})
      response = json_response(conn, 200)
      assert response["ok"] == true
    end

    test "returns 422 without email", %{conn: conn} do
      conn = post(conn, "/api/auth/magic-link", %{})
      assert json_response(conn, 422)
    end

    test "still returns ok when mail delivery raises", %{conn: conn} do
      original_mailer_config = Application.get_env(:uptrack, Uptrack.Mailer)

      Application.put_env(:uptrack, Uptrack.Mailer,
        Keyword.put(original_mailer_config, :adapter, Uptrack.TestSupport.RaisingMailerAdapter)
      )

      on_exit(fn ->
        Application.put_env(:uptrack, Uptrack.Mailer, original_mailer_config)
      end)

      conn =
        conn
        |> put_req_header("origin", "http://localhost:3000")
        |> post("/api/auth/magic-link", %{"email" => "new@example.com"})

      response = json_response(conn, 200)

      assert response["ok"] == true
      assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:3000"]
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
