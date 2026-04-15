defmodule Uptrack.Monitoring.MonitorCheck do
  @moduledoc """
  In-memory struct representing the result of a monitor check.

  No longer backed by a database table — all check data is stored in
  VictoriaMetrics. This struct exists solely to satisfy pattern matches
  and function signatures throughout the codebase.
  """

  @statuses ~w(up down paused)

  defstruct [
    :id,
    :monitor_id,
    :region_id,
    :status,
    :response_time,
    :status_code,
    :checked_at,
    :error_message,
    :response_body,
    :response_headers,
    :check_region,
    :region_results,
    :inserted_at,
    :updated_at
  ]

  def statuses, do: @statuses
end
