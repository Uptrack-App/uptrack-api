defmodule Uptrack.MCP.Server do
  @moduledoc "MCP Server for Uptrack — handles JSON-RPC protocol messages."

  alias Uptrack.MCP.{JsonRpc, Tools, Resources, Prompts}
  alias Uptrack.OAuth.Scopes

  require Logger

  def handle_message(message_json, org_id, scopes \\ :all) do
    case Jason.decode(message_json) do
      {:ok, message} ->
        response = handle_mcp_message(message, org_id, scopes)
        Jason.encode!(response)

      {:error, _} ->
        Jason.encode!(JsonRpc.error_response(nil, -32_700, "Parse error"))
    end
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "initialize", "id" => id}, _org_id, _scopes) do
    JsonRpc.success_response(id, %{
      "protocolVersion" => JsonRpc.protocol_version(),
      "capabilities" => %{"tools" => %{}, "resources" => %{}, "prompts" => %{}},
      "serverInfo" => %{"name" => "uptrack-mcp-server", "version" => "1.0.0"},
      "instructions" => server_instructions()
    })
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}, _org_id, _scopes) do
    JsonRpc.success_response(id, %{"tools" => Tools.definitions()})
  end

  defp handle_mcp_message(
         %{"jsonrpc" => "2.0", "method" => "tools/call", "id" => id, "params" => %{"name" => tool_name} = params},
         org_id,
         scopes
       ) do
    arguments = Map.get(params, "arguments", %{})
    Logger.debug("MCP: tools/call #{tool_name}")

    if scope_authorized?(scopes, tool_name) do
      result = Tools.call(tool_name, arguments, org_id)
      JsonRpc.tool_response(id, result)
    else
      required = Scopes.required_scope(tool_name)
      JsonRpc.error_response(id, -32_003, "Insufficient permissions: #{required} scope required")
    end
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "resources/list", "id" => id}, _org_id, _scopes) do
    JsonRpc.success_response(id, %{"resources" => Resources.definitions()})
  end

  defp handle_mcp_message(
         %{"jsonrpc" => "2.0", "method" => "resources/read", "id" => id, "params" => %{"uri" => uri}},
         org_id,
         _scopes
       ) do
    case Resources.read(uri, org_id) do
      {:ok, content} ->
        JsonRpc.success_response(id, %{
          "contents" => [%{"uri" => uri, "mimeType" => "application/json", "text" => content}]
        })
      {:error, reason} ->
        JsonRpc.error_response(id, -32_002, reason)
    end
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "ping", "id" => id}, _org_id, _scopes) do
    JsonRpc.success_response(id, %{})
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _org_id, _scopes) do
    %{"jsonrpc" => "2.0"}
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => "prompts/list", "id" => id}, _org_id, _scopes) do
    JsonRpc.success_response(id, %{"prompts" => Prompts.definitions()})
  end

  defp handle_mcp_message(
         %{"jsonrpc" => "2.0", "method" => "prompts/get", "id" => id, "params" => %{"name" => name} = params},
         org_id,
         _scopes
       ) do
    arguments = Map.get(params, "arguments", %{})

    case Prompts.get(name, arguments, org_id) do
      {:ok, prompt} -> JsonRpc.success_response(id, prompt)
      {:error, reason} -> JsonRpc.error_response(id, -32_002, reason)
    end
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0", "method" => _method, "id" => id}, _org_id, _scopes) do
    JsonRpc.error_response(id, -32_601, "Method not found")
  end

  defp handle_mcp_message(%{"jsonrpc" => "2.0"}, _org_id, _scopes) do
    %{"jsonrpc" => "2.0"}
  end

  defp handle_mcp_message(_message, _org_id, _scopes) do
    JsonRpc.error_response(nil, -32_600, "Invalid Request")
  end

  # API key and session auth get :all scopes (backward compatible)
  defp scope_authorized?(:all, _tool_name), do: true
  defp scope_authorized?(scopes, tool_name) when is_list(scopes), do: Scopes.authorized?(scopes, tool_name)

  defp server_instructions do
    """
    Uptrack is an uptime monitoring platform. You can manage monitors, view incidents, check analytics, and manage status pages.

    ## Available Tools

    | Need | Tool |
    |------|------|
    | Check if services are up | `list_monitors` |
    | Get detailed monitor info + uptime % | `get_monitor` |
    | Create a new monitor | `create_monitor` |
    | Pause/resume monitoring | `pause_monitor` / `resume_monitor` |
    | View recent incidents | `list_incidents` |
    | Acknowledge an incident | `acknowledge_incident` |
    | Dashboard overview | `get_dashboard_stats` |
    | Response time trends | `get_monitor_analytics` |
    | View status pages | `list_status_pages` |
    | View alert channels | `list_alert_channels` |
    | Add an alert channel | `create_alert_channel` |

    ## Resources (read-only data)
    - `uptrack://monitors` — all monitors with status and uptime
    - `uptrack://incidents` — 50 most recent incidents
    - `uptrack://dashboard` — aggregate stats

    ## Prompts (guided workflows)
    - `daily-report` — generate a daily uptime briefing
    - `incident-summary` — summarize incidents for a monitor
    - `monitor-health-check` — deep-dive health assessment for a monitor

    ## Quick Start
    - Use `list_monitors` to see all monitors and their current status
    - Use `get_dashboard_stats` for a quick overview of uptime and incidents
    - Use `create_monitor` to add a new URL to monitor
    - Use the `daily-report` prompt for an AI-guided daily briefing
    """
  end
end
