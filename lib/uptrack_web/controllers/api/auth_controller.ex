defmodule UptrackWeb.Api.AuthController do
  use UptrackWeb, :controller

  alias Uptrack.Accounts
  alias Uptrack.Auth
  alias Uptrack.Organizations

  require Logger

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
    if Uptrack.AbusePrevention.disposable_email?(email) do
      conn
      |> put_status(:unprocessable_entity)
      |> put_view(json: UptrackWeb.Api.ErrorJSON)
      |> render(:error, message: "Disposable email addresses are not allowed. Please use a permanent email.")
    else
      register_user(conn, name, email, password)
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Name, email, and password are required")
  end

  defp register_user(conn, name, email, password) do
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

  # --- Magic Link Authentication ---

  alias Uptrack.Auth.MagicLink
  alias Uptrack.Emails.MagicLinkEmail
  alias Uptrack.Mailer

  @doc """
  Sends a magic link email for passwordless authentication.
  POST /api/auth/magic-link
  """
  def magic_link(conn, %{"email" => email}) when is_binary(email) do
    if Uptrack.AbusePrevention.disposable_email?(email) do
      # Silently accept to prevent enumeration — but don't send email
      json(conn, %{ok: true, message: "If this email exists, you'll receive a sign-in link shortly."})
    else
      magic_link_send(conn, email)
    end
  end

  def magic_link(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Email is required")
  end

  defp magic_link_send(conn, email) do
    bucket = "magic_link:#{String.downcase(email)}"

    case Hammer.check_rate(bucket, 300_000, 3) do
      {:allow, _} ->
        {raw_token, hashed_token} = MagicLink.generate_token()

        case Accounts.store_magic_token(email, hashed_token) do
          {:ok, _token} ->
            case MagicLinkEmail.magic_link_email(email, raw_token) |> Mailer.deliver() do
              {:ok, _} -> Logger.info("Magic link email sent to #{email}")
              {:error, reason} -> Logger.error("Magic link email failed for #{email}: #{inspect(reason)}")
            end
          {:error, reason} ->
            Logger.error("Magic link token store failed: #{inspect(reason)}")
        end

        # Always return 200 to prevent email enumeration
        json(conn, %{ok: true, message: "If this email exists, you'll receive a sign-in link shortly."})

      {:deny, _} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: "Too many requests. Try again in a few minutes."})
    end
  end

  @doc """
  Verifies a magic link token and creates a session.
  POST /api/auth/magic-link/verify
  """
  def magic_link_verify(conn, %{"email" => email, "token" => token})
      when is_binary(email) and is_binary(token) do
    with {:ok, token_record} <- Accounts.verify_magic_token(email, token),
         {:ok, _consumed} <- Accounts.consume_magic_token(token_record),
         {:ok, user} <- Accounts.find_or_create_user_by_email(email) do
      org = Organizations.get_organization!(user.organization_id)

      conn
      |> put_session(:user_id, user.id)
      |> json(%{
        user: %{id: user.id, email: user.email, name: user.name, role: user.role},
        organization: %{id: org.id, name: org.name, plan: org.plan}
      })
    else
      {:error, :invalid_token} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Invalid token"})

      {:error, :token_expired} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Token expired"})

      {:error, :token_already_used} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Token already used"})

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> json(%{error: "Something went wrong"})
    end
  end

  def magic_link_verify(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: UptrackWeb.Api.ErrorJSON)
    |> render(:error, message: "Email and token are required")
  end

  @doc """
  Redirect-based magic link verification.
  GET /api/auth/magic-link/callback?token=...&email=...

  Email links here directly → verifies token → sets session cookie
  (same-origin, SameSite=Lax safe) → redirects to frontend dashboard.
  Same pattern as Google/GitHub OAuth callbacks.
  """
  def magic_link_callback(conn, %{"email" => email, "token" => token})
      when is_binary(email) and is_binary(token) do
    frontend = Application.get_env(:uptrack, :frontend_url, "http://localhost:3000")

    with {:ok, token_record} <- Accounts.verify_magic_token(email, token),
         {:ok, _consumed} <- Accounts.consume_magic_token(token_record),
         {:ok, user} <- Accounts.find_or_create_user_by_email(email) do
      Logger.info("Magic link callback: signed in #{email}")

      conn
      |> put_session(:user_id, user.id)
      |> redirect(external: "#{frontend}/dashboard")
    else
      {:error, reason} ->
        error = case reason do
          :invalid_token -> "invalid"
          :token_expired -> "expired"
          :token_already_used -> "used"
          _ -> "error"
        end

        conn
        |> redirect(external: "#{frontend}/login?error=#{error}")
    end
  end

  def magic_link_callback(conn, _params) do
    frontend = Application.get_env(:uptrack, :frontend_url, "http://localhost:3000")
    redirect(conn, external: "#{frontend}/login?error=invalid")
  end
end
