defmodule Uptrack.OAuth.Scopes do
  @moduledoc """
  OAuth 2.0 scope definitions for the Uptrack MCP connector.

  Maps resource types to read/write scopes. Pure data — no side effects.
  """

  @all_scopes ~w(
    monitors:read monitors:write
    incidents:read incidents:write
    status_pages:read
    alerts:read alerts:write
    analytics:read
  )

  @read_scopes ~w(monitors:read incidents:read status_pages:read alerts:read analytics:read)

  @scope_to_tools %{
    "monitors:read" => ~w(list_monitors get_monitor get_monitor_analytics),
    "monitors:write" => ~w(create_monitor delete_monitor pause_monitor resume_monitor),
    "incidents:read" => ~w(list_incidents),
    "incidents:write" => ~w(acknowledge_incident),
    "status_pages:read" => ~w(list_status_pages),
    "alerts:read" => ~w(list_alert_channels),
    "alerts:write" => ~w(create_alert_channel),
    "analytics:read" => ~w(get_dashboard_stats get_monitor_analytics)
  }

  def all_scopes, do: @all_scopes
  def read_scopes, do: @read_scopes

  @doc "Returns the required scope for a given MCP tool name."
  def required_scope(tool_name) do
    Enum.find_value(@scope_to_tools, fn {scope, tools} ->
      if tool_name in tools, do: scope
    end)
  end

  @doc "Checks if the given scopes authorize the tool."
  def authorized?(scopes, tool_name) when is_list(scopes) do
    case required_scope(tool_name) do
      nil -> true
      required -> required in scopes
    end
  end
end
