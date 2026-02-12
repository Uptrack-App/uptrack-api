defmodule UptrackWeb.SessionControllerTest do
  use UptrackWeb.ConnCase

  alias Uptrack.Accounts

  @moduletag :capture_log

  defp register_user(email, password) do
    {:ok, user} =
      Accounts.register_user_with_organization(%{
        "name" => "Test User",
        "email" => email,
        "password" => password
      })

    user
  end

  describe "POST /auth/register" do
    test "registers a new user and redirects to dashboard", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/register", %{
          "user" => %{
            "name" => "New User",
            "email" => "new@example.com",
            "password" => "secure_password_123"
          }
        })

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, :user_id)
    end

    test "redirects back on invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/register", %{
          "user" => %{
            "email" => "",
            "password" => "short"
          }
        })

      assert redirected_to(conn) == ~p"/auth/signup"
      assert Phoenix.Flash.get(conn.assigns.flash, :error)
    end
  end

  describe "POST /auth/login" do
    test "logs in with valid credentials", %{conn: conn} do
      user = register_user("login_test@example.com", "test_password_123")

      conn =
        post(conn, ~p"/auth/login", %{
          "user" => %{
            "email" => user.email,
            "password" => "test_password_123"
          }
        })

      assert redirected_to(conn) == ~p"/dashboard"
      assert get_session(conn, :user_id) == user.id
    end

    test "rejects invalid password", %{conn: conn} do
      user = register_user("bad_pass@example.com", "test_password_123")

      conn =
        post(conn, ~p"/auth/login", %{
          "user" => %{
            "email" => user.email,
            "password" => "wrong_password"
          }
        })

      assert redirected_to(conn) == ~p"/auth/signup"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "rejects nonexistent email", %{conn: conn} do
      conn =
        post(conn, ~p"/auth/login", %{
          "user" => %{
            "email" => "nobody@example.com",
            "password" => "whatever"
          }
        })

      assert redirected_to(conn) == ~p"/auth/signup"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end
  end
end
