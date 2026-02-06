defmodule UptrackWeb.AuthController do
  use UptrackWeb, :controller
  alias Uptrack.Accounts
  alias Uptrack.Accounts.User

  def request(conn, _params) do
    redirect(conn, external: Ueberauth.request_url(:github, conn))
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, params) do
    case auth_params_from_ueberauth(auth) do
      {:ok, user_params} ->
        case Accounts.get_user_by_email(user_params.email) do
          nil ->
            case Accounts.create_user_from_oauth_with_organization(user_params) do
              {:ok, user} ->
                conn
                |> put_session(:user_id, user.id)
                |> put_flash(:info, "Successfully signed up!")
                |> redirect(to: ~p"/dashboard")

              {:error, _step, _changeset, _changes} ->
                conn
                |> put_flash(:error, "Something went wrong")
                |> redirect(to: ~p"/auth/signup")
            end

          user ->
            conn
            |> put_session(:user_id, user.id)
            |> put_flash(:info, "Welcome back!")
            |> redirect(to: ~p"/dashboard")
        end

      {:error, reason} ->
        conn
        |> put_flash(:error, reason)
        |> redirect(to: ~p"/auth/signup")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: ~p"/auth/signup")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Successfully logged out")
    |> redirect(to: ~p"/")
  end

  defp auth_params_from_ueberauth(%{provider: provider, info: info, uid: uid}) do
    email = info.email
    name = info.name || "#{info.first_name} #{info.last_name}"

    if email do
      {:ok,
       %{
         email: email,
         name: name,
         provider: Atom.to_string(provider),
         provider_id: uid
       }}
    else
      {:error, "No email address provided"}
    end
  end

  defp auth_params_from_ueberauth(_), do: {:error, "Invalid authentication data"}
end
