defmodule Uptrack.Reports.ReportBuilder do
  @moduledoc """
  Pure module — builds weekly report data from monitoring stats.
  No database calls, no side effects.
  """

  @doc """
  Builds a report summary from raw monitoring data.

  Takes a map with :monitors, :uptime_data, :incident_count, :period and
  returns a structured report map ready for email rendering.
  """
  def build_summary(%{monitors: monitors, uptime_data: uptime_data, incident_count: incident_count, period: period}) do
    total_monitors = length(monitors)
    active_monitors = Enum.count(monitors, &(&1.is_active))

    overall_uptime =
      if uptime_data == [] do
        100.0
      else
        uptime_data
        |> Enum.map(& &1.uptime)
        |> then(fn vals -> Enum.sum(vals) / length(vals) end)
        |> Float.round(2)
      end

    monitor_breakdown =
      Enum.map(monitors, fn monitor ->
        monitor_uptime =
          uptime_data
          |> Enum.filter(&(&1.monitor_id == monitor.id))
          |> Enum.map(& &1.uptime)
          |> then(fn
            [] -> 100.0
            vals -> Enum.sum(vals) / length(vals) |> Float.round(2)
          end)

        %{
          name: monitor.name,
          url: monitor.url,
          uptime: monitor_uptime,
          status: if(monitor.is_active, do: "active", else: "paused")
        }
      end)

    %{
      period: period,
      total_monitors: total_monitors,
      active_monitors: active_monitors,
      overall_uptime: overall_uptime,
      incident_count: incident_count,
      monitor_breakdown: monitor_breakdown,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end
end
