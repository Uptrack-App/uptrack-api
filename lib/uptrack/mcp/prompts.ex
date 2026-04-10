defmodule Uptrack.MCP.Prompts do
  @moduledoc "MCP Prompt templates for common Uptrack monitoring workflows."

  def definitions do
    [
      %{
        "name" => "daily-report",
        "description" => "Generate a daily uptime briefing covering monitor health and recent incidents.",
        "arguments" => []
      },
      %{
        "name" => "incident-summary",
        "description" => "Summarize recent incidents for a specific monitor.",
        "arguments" => [
          %{
            "name" => "monitor_name",
            "description" => "Name or URL of the monitor to summarize incidents for",
            "required" => true
          }
        ]
      },
      %{
        "name" => "monitor-health-check",
        "description" => "Perform a deep-dive health assessment for a single monitor.",
        "arguments" => [
          %{
            "name" => "monitor_id",
            "description" => "ID of the monitor to assess",
            "required" => true
          }
        ]
      }
    ]
  end

  def get("daily-report", _arguments, _org_id) do
    {:ok, %{
      "description" => "Daily uptime briefing",
      "messages" => [
        %{
          "role" => "user",
          "content" => %{
            "type" => "text",
            "text" => """
            Please generate a daily uptime report for my infrastructure. Follow these steps:

            1. Call `get_dashboard_stats` to get an overall summary
            2. Call `list_monitors` to see the status of all monitors
            3. Call `list_incidents` with limit 20 to see recent incidents

            Then produce a concise daily briefing covering:
            - Overall uptime percentage (30-day)
            - How many monitors are up vs down
            - Any ongoing incidents
            - Notable incidents from the last 24 hours
            - Any monitors with degraded performance
            """
          }
        }
      ]
    }}
  end

  def get("incident-summary", %{"monitor_name" => monitor_name}, _org_id) do
    {:ok, %{
      "description" => "Incident summary for #{monitor_name}",
      "messages" => [
        %{
          "role" => "user",
          "content" => %{
            "type" => "text",
            "text" => """
            Please summarize recent incidents for the monitor "#{monitor_name}".

            1. Call `list_monitors` to find the monitor ID for "#{monitor_name}"
            2. Call `list_incidents` with limit 50 to get recent incidents
            3. Filter incidents for the monitor matching "#{monitor_name}"
            4. Call `get_monitor_analytics` for that monitor to get uptime trends

            Produce a summary covering:
            - Total incidents in the last 30 days
            - Average incident duration
            - Most common causes
            - Current uptime percentage
            - Recommendations if reliability is below 99.9%
            """
          }
        }
      ]
    }}
  end

  def get("monitor-health-check", %{"monitor_id" => monitor_id}, _org_id) do
    {:ok, %{
      "description" => "Health check for monitor #{monitor_id}",
      "messages" => [
        %{
          "role" => "user",
          "content" => %{
            "type" => "text",
            "text" => """
            Please perform a health assessment for monitor ID "#{monitor_id}".

            1. Call `get_monitor` with monitor_id "#{monitor_id}" for current status and uptime
            2. Call `get_monitor_analytics` with monitor_id "#{monitor_id}" and days 30 for trends
            3. Call `list_incidents` and filter for this monitor's incidents

            Produce a health report covering:
            - Current status and response time
            - 30-day uptime percentage with trend (improving/degrading)
            - Response time trends (P50/P95 if available)
            - Recent incident history
            - Overall health score (Excellent/Good/Fair/Poor)
            - Action items if health score is Fair or Poor
            """
          }
        }
      ]
    }}
  end

  def get(name, _arguments, _org_id) do
    {:error, "Unknown prompt: #{name}"}
  end
end
