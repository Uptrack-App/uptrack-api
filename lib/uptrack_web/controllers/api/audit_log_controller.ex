defmodule UptrackWeb.Api.AuditLogController do
  use UptrackWeb, :controller

  alias Uptrack.Teams

  action_fallback UptrackWeb.Api.FallbackController

  @doc """
  Lists audit logs for the organization.
  GET /api/organizations/:org_id/audit-logs
  """
  def index(conn, %{"organization_id" => org_id} = params) do
    with :ok <- authorize_admin(conn, org_id) do
      since = parse_since(params["since"])

      opts = [
        limit: parse_int(params["limit"], 50),
        offset: parse_int(params["offset"], 0),
        action: params["action"],
        user_id: params["user_id"],
        since: since
      ]

      logs = Teams.list_audit_logs(org_id, opts)
      total = Teams.count_audit_logs(org_id, action: params["action"], user_id: params["user_id"], since: since)

      render(conn, :index, logs: logs, total: total)
    end
  end

  # Authorization - only admins and owners can view audit logs
  defp authorize_admin(conn, org_id) do
    user = conn.assigns.current_user

    if user.organization_id == org_id and user.role in [:owner, :admin] do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_since(nil), do: nil

  defp parse_since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
