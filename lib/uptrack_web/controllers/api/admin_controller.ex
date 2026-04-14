defmodule UptrackWeb.Api.AdminController do
  use UptrackWeb, :controller

  alias Uptrack.{Accounts, Admin, Teams}

  @doc """
  POST /api/admin/impersonate
  Starts an impersonation session. Session-based auth only.
  """
  def start_impersonation(conn, %{"target_user_id" => target_user_id}) do
    admin = conn.assigns.current_user

    # Admin pipeline has no ImpersonationPlug — read session directly
    if get_session(conn, :impersonating_user_id) do
      conn
      |> put_status(:conflict)
      |> json(%{error: "already_impersonating"})
    else
      with :ok <- check_session_auth(conn),
           {:ok, target} <- find_target_user(target_user_id),
           :ok <- check_not_self(admin, target),
           :ok <- check_not_admin(target) do
        Teams.log_action(
          target.organization_id,
          admin.id,
          "admin.impersonation_started",
          "user",
          target.id,
          metadata: %{admin_id: admin.id, admin_email: admin.email}
        )

        conn
        |> put_session(:impersonating_user_id, target.id)
        |> put_session(:impersonation_started_at, DateTime.utc_now() |> DateTime.to_iso8601())
        |> put_status(:ok)
        |> render(:impersonation_started, target: target)
      else
        {:error, :session_required} ->
          conn |> put_status(:forbidden) |> json(%{error: "session_auth_required"})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "user_not_found"})

        {:error, :self_impersonation} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "cannot_impersonate_self"})

        {:error, :target_is_admin} ->
          conn |> put_status(:forbidden) |> json(%{error: "cannot_impersonate_admin"})
      end
    end
  end

  def start_impersonation(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "target_user_id is required"})
  end

  @doc """
  DELETE /api/admin/impersonate
  Stops the active impersonation session.
  """
  def stop_impersonation(conn, _params) do
    admin = conn.assigns.current_user

    # Log if there was an active impersonation to end
    if impersonated_id = get_session(conn, :impersonating_user_id) do
      target = Accounts.get_user(impersonated_id)

      Teams.log_action(
        (if target, do: target.organization_id, else: admin.organization_id),
        admin.id,
        "admin.impersonation_ended",
        "user",
        impersonated_id,
        metadata: %{admin_id: admin.id, admin_email: admin.email}
      )
    end

    conn
    |> delete_session(:impersonating_user_id)
    |> delete_session(:impersonation_started_at)
    |> put_status(:ok)
    |> render(:impersonation_stopped, admin: admin)
  end

  @doc """
  GET /api/admin/users?q=&page=&per_page=
  Searches users across all organizations.
  """
  def search_users(conn, params) do
    query = Map.get(params, "q", "")
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 25)

    result = Admin.search_users(query, page: page, per_page: per_page)
    render(conn, :users, result: result)
  end

  @doc """
  GET /api/admin/organizations?q=&page=&per_page=
  Searches organizations across the platform.
  """
  def search_organizations(conn, params) do
    query = Map.get(params, "q", "")
    page = parse_int(params["page"], 1)
    per_page = parse_int(params["per_page"], 25)

    result = Admin.search_organizations(query, page: page, per_page: per_page)
    render(conn, :organizations, result: result)
  end

  # --- Private helpers ---

  defp check_session_auth(conn) do
    if conn.assigns[:auth_method] == :session do
      :ok
    else
      {:error, :session_required}
    end
  end

  defp find_target_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp check_not_self(admin, target) do
    if admin.id == target.id do
      {:error, :self_impersonation}
    else
      :ok
    end
  end

  defp check_not_admin(target) do
    if target.is_admin do
      {:error, :target_is_admin}
    else
      :ok
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end
  defp parse_int(val, _default) when is_integer(val), do: val
  defp parse_int(_, default), do: default
end
