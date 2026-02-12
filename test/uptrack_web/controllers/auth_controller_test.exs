defmodule UptrackWeb.AuthControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Accounts

  @moduletag :capture_log

  defp build_ueberauth_auth(overrides) do
    %Ueberauth.Auth{
      provider: Map.get(overrides, :provider, :github),
      uid: Map.get(overrides, :uid, "github-uid-#{System.unique_integer([:positive])}"),
      info: %Ueberauth.Auth.Info{
        email: Map.get(overrides, :email, "oauth-#{System.unique_integer([:positive])}@example.com"),
        name: Map.get(overrides, :name, "Test User"),
        first_name: Map.get(overrides, :first_name, "Test"),
        last_name: Map.get(overrides, :last_name, "User")
      }
    }
  end

  describe "callback/2 with successful auth" do
    test "creates a new user and redirects to dashboard", %{conn: conn} do
      auth = build_ueberauth_auth(%{email: "newuser@example.com", name: "New User"})

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> UptrackWeb.AuthController.callback(%{})

      assert redirected_to(conn) =~ "/dashboard"
      assert get_session(conn, :user_id)

      user = Accounts.get_user_by_email("newuser@example.com")
      assert user
      assert user.name == "New User"
      assert user.provider == "github"
    end

    test "logs in existing user and redirects to dashboard", %{conn: conn} do
      # First create a user via OAuth
      auth = build_ueberauth_auth(%{email: "existing@example.com", name: "Existing User"})

      conn1 =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> UptrackWeb.AuthController.callback(%{})

      user_id = get_session(conn1, :user_id)
      assert user_id

      # Now log in again with the same email
      conn2 =
        build_conn()
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> UptrackWeb.AuthController.callback(%{})

      assert redirected_to(conn2) =~ "/dashboard"
      assert get_session(conn2, :user_id) == user_id
    end

    test "redirects with error when email is nil", %{conn: conn} do
      auth = build_ueberauth_auth(%{email: nil})

      conn =
        conn
        |> init_test_session(%{})
        |> assign(:ueberauth_auth, auth)
        |> UptrackWeb.AuthController.callback(%{})

      location = redirected_to(conn)
      assert location =~ "/login"
      assert location =~ "error=no_email"
    end
  end

  describe "callback/2 with auth failure" do
    test "redirects to login with error when ueberauth_auth is not assigned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> UptrackWeb.AuthController.callback(%{})

      location = redirected_to(conn)
      assert location =~ "/login"
      assert location =~ "error=auth_failed"
    end
  end

  describe "logout/2" do
    test "clears session and redirects to frontend", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{user_id: "some-id"})
        |> UptrackWeb.AuthController.logout(%{})

      assert redirected_to(conn) =~ "localhost:3000"
      refute get_session(conn, :user_id)
    end
  end
end
