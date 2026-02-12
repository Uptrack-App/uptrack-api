defmodule UptrackWeb.Api.AuthControllerTest do
  use UptrackWeb.ConnCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Accounts

  @moduletag :capture_log

  describe "POST /api/auth/register" do
    test "registers a new user and returns user with session", %{conn: conn} do
      conn =
        post(conn, "/api/auth/register", %{
          "name" => "New User",
          "email" => "new@example.com",
          "password" => "secure_password_123"
        })

      response = json_response(conn, 201)
      assert response["user"]["name"] == "New User"
      assert response["user"]["email"] == "new@example.com"
      assert response["organization"]["name"] =~ "Organization"
      assert get_session(conn, :user_id)
    end

    test "returns error on invalid data", %{conn: conn} do
      conn =
        post(conn, "/api/auth/register", %{
          "name" => "",
          "email" => "bad",
          "password" => "short"
        })

      response = json_response(conn, 422)
      assert response["error"]
    end

    test "returns error on duplicate email", %{conn: conn} do
      {user, _org} = user_with_org_fixture()

      conn =
        post(conn, "/api/auth/register", %{
          "name" => "Another",
          "email" => user.email,
          "password" => "secure_password_123"
        })

      response = json_response(conn, 422)
      assert response["error"]
    end

    test "returns error when missing required fields", %{conn: conn} do
      conn = post(conn, "/api/auth/register", %{})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "required"
    end
  end

  describe "POST /api/auth/login" do
    setup do
      {:ok, user} =
        Accounts.register_user_with_organization(%{
          "name" => "Test User",
          "email" => "login@example.com",
          "password" => "secure_password_123"
        })

      %{user: user}
    end

    test "logs in with valid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/auth/login", %{
          "email" => user.email,
          "password" => "secure_password_123"
        })

      response = json_response(conn, 200)
      assert response["user"]["email"] == user.email
      assert response["organization"]
      assert get_session(conn, :user_id) == user.id
    end

    test "rejects invalid password", %{conn: conn, user: user} do
      conn =
        post(conn, "/api/auth/login", %{
          "email" => user.email,
          "password" => "wrong_password"
        })

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "Invalid"
    end

    test "rejects nonexistent email", %{conn: conn} do
      conn =
        post(conn, "/api/auth/login", %{
          "email" => "nobody@example.com",
          "password" => "whatever12345"
        })

      response = json_response(conn, 401)
      assert response["error"]["message"] =~ "Invalid"
    end
  end

  describe "GET /api/auth/me" do
    test "returns current user when authenticated", %{conn: conn} do
      %{conn: conn, user: user, org: org} = setup_api_auth(conn)

      conn = get(conn, "/api/auth/me")

      response = json_response(conn, 200)
      assert response["user"]["id"] == user.id
      assert response["user"]["email"] == user.email
      assert response["organization"]["id"] == org.id
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, "/api/auth/me")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/auth/logout" do
    test "clears the session", %{conn: conn} do
      %{conn: conn} = setup_api_auth(conn)

      conn = post(conn, "/api/auth/logout")

      response = json_response(conn, 200)
      assert response["ok"] == true
    end
  end

  describe "PATCH /api/auth/profile" do
    test "updates the user's name", %{conn: conn} do
      %{conn: conn} = setup_api_auth(conn)

      conn = patch(conn, "/api/auth/profile", %{"name" => "Updated Name"})

      response = json_response(conn, 200)
      assert response["user"]["name"] == "Updated Name"
    end
  end

  describe "PATCH /api/auth/password" do
    test "changes password with valid current password", %{conn: conn} do
      {:ok, user} =
        Accounts.register_user_with_organization(%{
          "name" => "Pass User",
          "email" => "pass@example.com",
          "password" => "old_password_123"
        })

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(user_id: user.id)
        |> patch("/api/auth/password", %{
          "current_password" => "old_password_123",
          "new_password" => "new_password_456"
        })

      response = json_response(conn, 200)
      assert response["user"]

      # Verify new password works
      updated_user = Accounts.get_user!(user.id)
      assert Uptrack.Accounts.User.valid_password?(updated_user, "new_password_456")
    end

    test "rejects wrong current password", %{conn: conn} do
      {:ok, user} =
        Accounts.register_user_with_organization(%{
          "name" => "Pass User 2",
          "email" => "pass2@example.com",
          "password" => "old_password_123"
        })

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(user_id: user.id)
        |> patch("/api/auth/password", %{
          "current_password" => "wrong_password",
          "new_password" => "new_password_456"
        })

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "incorrect"
    end
  end

  describe "DELETE /api/auth/account" do
    test "deletes account with valid password", %{conn: conn} do
      {:ok, user} =
        Accounts.register_user_with_organization(%{
          "name" => "Delete User",
          "email" => "delete@example.com",
          "password" => "delete_password_123"
        })

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(user_id: user.id)
        |> delete("/api/auth/account", %{"password" => "delete_password_123"})

      response = json_response(conn, 200)
      assert response["ok"] == true

      # User should be deleted
      assert_raise Ecto.NoResultsError, fn -> Accounts.get_user!(user.id) end
    end

    test "rejects wrong password", %{conn: conn} do
      {:ok, user} =
        Accounts.register_user_with_organization(%{
          "name" => "Delete User 2",
          "email" => "delete2@example.com",
          "password" => "delete_password_123"
        })

      conn =
        conn
        |> Phoenix.ConnTest.init_test_session(user_id: user.id)
        |> delete("/api/auth/account", %{"password" => "wrong_password"})

      response = json_response(conn, 422)
      assert response["error"]["message"] =~ "incorrect"
    end
  end
end
