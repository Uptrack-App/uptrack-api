defmodule UptrackWeb.Plugs.Impersonation do
  @moduledoc """
  Plug that activates impersonation when session keys are present.

  Must run after ApiAuth. Only activates for session-based auth (not API keys).

  When active:
  - Replaces conn.assigns.current_user with the target (impersonated) user
  - Sets conn.assigns.impersonating_admin to the real admin user
  - Reloads conn.assigns.current_organization from the target user's org

  Handles:
  - 1-hour hard timeout → 403 impersonation_expired + audit log
  - Deleted target user → clears session, continues as admin
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Uptrack.{Accounts, Organizations, Teams}

  @timeout_seconds 3600

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:auth_method] == :session do
      maybe_impersonate(conn)
    else
      conn
    end
  end

  defp maybe_impersonate(conn) do
    case get_session(conn, :impersonating_user_id) do
      nil -> conn
      target_user_id -> activate_impersonation(conn, target_user_id)
    end
  end

  defp activate_impersonation(conn, target_user_id) do
    started_at_str = get_session(conn, :impersonation_started_at)
    admin = conn.assigns.current_user

    with {:ok, started_at} <- parse_started_at(started_at_str),
         :ok <- check_timeout(started_at, admin, conn),
         {:ok, target_user} <- load_target_user(target_user_id) do
      organization = Organizations.get_organization!(target_user.organization_id)

      conn
      |> assign(:current_user, target_user)
      |> assign(:current_organization, organization)
      |> assign(:impersonating_admin, admin)
    else
      {:error, :expired} ->
        conn
        |> delete_session(:impersonating_user_id)
        |> delete_session(:impersonation_started_at)
        |> put_status(:forbidden)
        |> put_view(json: UptrackWeb.Api.ErrorJSON)
        |> render(:error, message: "impersonation_expired")
        |> halt()

      {:error, :user_not_found} ->
        conn
        |> delete_session(:impersonating_user_id)
        |> delete_session(:impersonation_started_at)

      {:error, _} ->
        conn
        |> delete_session(:impersonating_user_id)
        |> delete_session(:impersonation_started_at)
    end
  end

  defp parse_started_at(nil), do: {:error, :missing}

  defp parse_started_at(started_at_str) do
    case DateTime.from_iso8601(started_at_str) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, :invalid}
    end
  end

  defp check_timeout(started_at, admin, conn) do
    elapsed = DateTime.diff(DateTime.utc_now(), started_at, :second)

    if elapsed > @timeout_seconds do
      Teams.log_action(
        admin.organization_id,
        admin.id,
        "admin.impersonation_expired",
        "user",
        get_session(conn, :impersonating_user_id),
        metadata: %{impersonating_user_id: get_session(conn, :impersonating_user_id)}
      )

      {:error, :expired}
    else
      :ok
    end
  end

  defp load_target_user(user_id) do
    {:ok, Accounts.get_user!(user_id)}
  rescue
    Ecto.NoResultsError -> {:error, :user_not_found}
  end
end
