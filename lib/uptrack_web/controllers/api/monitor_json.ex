defmodule UptrackWeb.Api.MonitorJSON do
  @moduledoc """
  JSON views for monitor endpoints.
  """

  alias Uptrack.Monitoring.{Monitor, MonitorCheck}

  def index(%{monitors: monitors}) do
    %{data: for(monitor <- monitors, do: monitor_data(monitor))}
  end

  def show(%{monitor: monitor}) do
    %{data: monitor_data(monitor)}
  end

  def checks(%{checks: checks}) do
    %{data: for(check <- checks, do: check_data(check))}
  end

  defp check_data(%MonitorCheck{} = check) do
    %{
      id: check.id,
      monitor_id: check.monitor_id,
      status: check.status,
      response_time: check.response_time,
      status_code: check.status_code,
      error_message: check.error_message,
      checked_at: check.checked_at
    }
  end

  defp monitor_data(%Monitor{} = monitor) do
    %{
      id: monitor.id,
      name: monitor.name,
      url: monitor.url,
      monitor_type: monitor.monitor_type,
      status: monitor.status,
      interval: monitor.interval,
      timeout: monitor.timeout,
      settings: monitor.settings,
      description: monitor.description,
      created_at: monitor.inserted_at,
      updated_at: monitor.updated_at
    }
  end
end
