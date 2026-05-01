defmodule UptrackWeb.AuthController do
  use UptrackWeb, :controller
  alias Uptrack.Accounts

  # The request action is called before Ueberauth redirects to the OAuth provider.
  # Ueberauth handles the redirect automatically via the plug, so we just return the conn.
  # For unknown/invalid providers Ueberauth passes through without halting, so we must
  # always send a response as a fallback.
  def request(conn, _params) do
    conn
    |> redirect(external: "#{frontend_url()}/login?error=auth_failed")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    frontend = frontend_url()

    case auth_params_from_ueberauth(auth) do
      {:ok, user_params} ->
        case Accounts.get_user_by_email(user_params.email) do
          nil ->
            case Accounts.create_user_from_oauth_with_organization(user_params) do
              {:ok, user} ->
                conn
                |> put_session(:user_id, user.id)
                |> redirect(external: "#{frontend}/dashboard")

              {:error, step, changeset, _changes} ->
                require Logger
                Logger.error("OAuth signup failed at step #{inspect(step)}: #{inspect(changeset.errors)}, params: #{inspect(Map.drop(user_params, [:provider_id]))}")
                conn
                |> redirect(external: "#{frontend}/login?error=signup_failed")
            end

          user ->
            conn
            |> put_session(:user_id, user.id)
            |> redirect(external: "#{frontend}/dashboard")
        end

      {:error, _reason} ->
        conn
        |> redirect(external: "#{frontend}/login?error=no_email")
    end
  end

  def callback(conn, _params) do
    frontend = frontend_url()

    conn
    |> redirect(external: "#{frontend}/login?error=auth_failed")
  end

  def logout(conn, _params) do
    frontend = frontend_url()

    conn
    |> clear_session()
    |> redirect(external: frontend)
  end

  defp auth_params_from_ueberauth(%{provider: provider, info: info, uid: uid}) do
    email = info.email

    name =
      [info.name, "#{info.first_name} #{info.last_name}", info.nickname, email]
      |> Enum.map(fn s -> if is_binary(s), do: String.trim(s), else: nil end)
      |> Enum.find(& &1 != nil and &1 != "")

    if email do
      {:ok,
       %{
         email: email,
         name: name || "User",
         provider: Atom.to_string(provider),
         provider_id: to_string(uid)
       }}
    else
      {:error, "No email address provided"}
    end
  end

  defp auth_params_from_ueberauth(_), do: {:error, "Invalid authentication data"}

  defp frontend_url do
    Application.get_env(:uptrack, :frontend_url, "http://localhost:3000")
  end
end
