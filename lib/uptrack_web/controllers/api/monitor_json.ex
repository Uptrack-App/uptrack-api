defmodule UptrackWeb.Api.MonitorJSON do
  @moduledoc """
  JSON views for monitor endpoints.
  """

  alias Uptrack.Monitoring.Monitor

  def index(%{monitors: monitors}) do
    %{data: for(monitor <- monitors, do: monitor_data(monitor))}
  end

  def show(%{monitor: monitor}) do
    %{data: monitor_data(monitor)}
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
