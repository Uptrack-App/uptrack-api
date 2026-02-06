defmodule UptrackWeb.Api.AuditLogJSON do
  @moduledoc """
  JSON views for audit log endpoints.
  """

  alias Uptrack.Teams.AuditLog

  def index(%{logs: logs, total: total}) do
    %{
      data: for(log <- logs, do: log_data(log)),
      meta: %{
        total: total
      }
    }
  end

  defp log_data(%AuditLog{} = log) do
    %{
      id: log.id,
      action: log.action,
      resource_type: log.resource_type,
      resource_id: log.resource_id,
      metadata: log.metadata,
      ip_address: log.ip_address,
      created_at: log.created_at,
      user:
        if log.user do
          %{
            id: log.user.id,
            name: log.user.name,
            email: log.user.email
          }
        end
    }
  end
end
