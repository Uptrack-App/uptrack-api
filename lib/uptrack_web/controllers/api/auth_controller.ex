defmodule UptrackWeb.Api.AuthController do
  use UptrackWeb, :controller

  alias Uptrack.Accounts
  alias Uptrack.Accounts.User
  alias Uptrack.Organizations

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Registers a new user with an organization and creates a session.
  POST /api/auth/register
  """
  def register(conn, %{"name" => name, "email" => email, "password" => password}) do
    case Accounts.register_user_with_organization(%{
           "name" => name,
           "email" => email,
           "password" => password
         }) do
      {:ok, user} ->
        user = Accounts.get_user!(user.id)
        org = Organizations.get_organization!(user.organization_id)

        conn
        |> put_session(:user_id, user.id)
        |> put_status(:created)
        |> render(:user, user: user, organization: org)

      {:error, :user, changeset, _} ->
        {:error, changeset}

      {:error, :organization, changeset, _} ->
        {:error, changeset}
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Name, email, and password are required")
  end

  @doc """
  Logs in with email and password.
  POST /api/auth/login
  """
  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email(email) do
      %User{} = user ->
        if User.valid_password?(user, password) do
          org = Organizations.get_organization!(user.organization_id)

          conn
          |> put_session(:user_id, user.id)
          |> render(:user, user: user, organization: org)
        else
          conn
          |> put_status(:unauthorized)
          |> put_view(json: UptrackWeb.Api.ErrorJSON)
          |> render(:error, message: "Invalid email or password")
        end

      nil ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()

        conn
        |> put_status(:unauthorized)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "Invalid email or password")
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Email and password are required")
  end

  @doc """
  Returns the current authenticated user.
  GET /api/auth/me
  """
  def me(conn, _params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    render(conn, :user, user: user, organization: org)
  end

  @doc """
  Logs out the current user.
  POST /api/auth/logout
  """
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> json(%{ok: true})
  end

  @doc """
  Updates the current user's profile (name).
  PATCH /api/auth/profile
  """
  def update_profile(conn, %{"name" => _} = params) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    case Accounts.update_user(user, Map.take(params, ["name"])) do
      {:ok, updated_user} ->
        render(conn, :user, user: updated_user, organization: org)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Changes the current user's password.
  PATCH /api/auth/password
  """
  def change_password(conn, %{
        "current_password" => current_password,
        "new_password" => new_password
      }) do
    user = conn.assigns.current_user
    org = conn.assigns.current_organization

    case Accounts.change_password(user, current_password, new_password) do
      {:ok, updated_user} ->
        render(conn, :user, user: updated_user, organization: org)

      {:error, :invalid_password} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "Current password is incorrect")

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes the current user's account and organization.
  DELETE /api/auth/account
  """
  def delete_account(conn, params) do
    user = conn.assigns.current_user
    password = params["password"]

    case Accounts.delete_user_and_organization(user, password) do
      {:ok, _} ->
        conn
        |> clear_session()
        |> json(%{ok: true})

      {:error, :invalid_password} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "Password is incorrect")

      {:error, reason} ->
        {:error, reason}
    end
  end
end
