defmodule UptrackWeb.Api.AuthController do
  use UptrackWeb, :controller

  alias Uptrack.Accounts
  alias Uptrack.Auth
  alias Uptrack.Organizations

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Returns which authentication providers are available.
  GET /api/auth/providers
  """
  def providers(conn, _params) do
    github_configured? =
      case Application.get_env(:ueberauth, Ueberauth.Strategy.Github.OAuth) do
        config when is_list(config) ->
          id = Keyword.get(config, :client_id)
          id != nil and id != "" and id != "not-set"

        _ ->
          false
      end

    google_configured? =
      case Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth) do
        config when is_list(config) ->
          id = Keyword.get(config, :client_id)
          id != nil and id != "" and id != "not-set"

        _ ->
          false
      end

    json(conn, %{
      providers: %{
        email: true,
        github: github_configured?,
        google: google_configured?
      }
    })
  end

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
  def login(conn, %{"email" => email, "password" => password} = params) do
    case Auth.authenticate(email, password) do
      {:ok, user} ->
        org = Organizations.get_organization!(user.organization_id)

        conn
        |> put_session(:user_id, user.id)
        |> render(:user, user: user, organization: org)

      {:totp_required, user} ->
        # 2FA enabled — check if TOTP code was provided in the same request
        case params["totp_code"] do
          code when is_binary(code) and code != "" ->
            case Auth.verify_second_factor(user.id, code) do
              {:ok, user} ->
                org = Organizations.get_organization!(user.organization_id)

                conn
                |> put_session(:user_id, user.id)
                |> render(:user, user: user, organization: org)

              {:error, :invalid_code} ->
                conn
                |> put_status(:unauthorized)
                |> put_view(json: UptrackWeb.Api.ErrorJSON)
                |> render(:error, message: "Invalid 2FA code")
            end

          _ ->
            # No TOTP code provided — store pending state in session, prompt for code
            conn
            |> put_session(:pending_2fa_user_id, user.id)
            |> put_status(200)
            |> json(%{totp_required: true})
        end

      {:error, :sso_enforced} ->
        conn
        |> put_status(:forbidden)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "Password login is disabled for this organization. Please sign in with SSO.")

      {:error, :invalid_credentials} ->
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
  Verifies a TOTP code after initial login returned totp_required.
  POST /api/auth/verify-2fa

  Uses session-stored pending_2fa_user_id (set during login) to prevent
  arbitrary user_id brute-force attacks.
  """
  def verify_2fa(conn, %{"code" => code}) do
    pending_user_id = get_session(conn, :pending_2fa_user_id)

    if is_nil(pending_user_id) do
      conn
      |> put_status(:unauthorized)
      |> put_view(json: UptrackWeb.Api.ErrorJSON)
      |> render(:error, message: "No pending 2FA session. Please log in first.")
    else
      conn = delete_session(conn, :pending_2fa_user_id)

      case Auth.verify_second_factor(pending_user_id, code) do
        {:ok, user} ->
          org = Organizations.get_organization!(user.organization_id)

          conn
          |> put_session(:user_id, user.id)
          |> render(:user, user: user, organization: org)

      {:error, :invalid_code} ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "Invalid 2FA code")
      end
    end
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
