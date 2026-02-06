defmodule UptrackWeb.SessionController do
  use UptrackWeb, :controller

  alias Uptrack.Accounts

  @doc """
  Creates a session after successful registration via LiveView.

  The LiveView validates the form and triggers a form submission here
  to set the session (which LiveViews cannot do directly).
  """
  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user_with_organization(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: ~p"/dashboard")

      {:error, _step, _changeset, _} ->
        conn
        |> put_flash(:error, "Registration failed. Please try again.")
        |> redirect(to: ~p"/auth/signup")
    end
  end

  @doc """
  Logs in a user via email and password.
  """
  def login(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        Bcrypt.no_user_verify()

        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/auth/signup")

      user ->
        if Accounts.User.valid_password?(user, password) do
          conn
          |> put_session(:user_id, user.id)
          |> put_flash(:info, "Welcome back!")
          |> redirect(to: ~p"/dashboard")
        else
          conn
          |> put_flash(:error, "Invalid email or password")
          |> redirect(to: ~p"/auth/signup")
        end
    end
  end
end
