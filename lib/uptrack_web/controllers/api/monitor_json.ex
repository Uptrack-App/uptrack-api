defmodule UptrackWeb.Api.MonitorJSON do
  @moduledoc """
  JSON views for monitor endpoints.
  """

  alias Uptrack.Monitoring.{Monitor, MonitorCheck}
  alias Uptrack.Metrics.Reader

  def index(%{result: %{monitors: monitors, total: total, page: page, per_page: per_page}}) do
    # Read from Nebulex cache (populated by MonitorProcess on every check)
    # Zero latency — no VM or Postgres query needed
    monitor_ids = Enum.map(monitors, & &1.id)
    latest_checks = Uptrack.Cache.get_latest_checks_batch(monitor_ids)

    %{
      data: for(monitor <- monitors, do: monitor_data(monitor, latest_checks)),
      meta: %{
        total: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(total / max(per_page, 1))
      }
    }
  end

  def show(%{monitor: monitor}) do
    latest_checks = Uptrack.Cache.get_latest_checks_batch([monitor.id])
    %{data: monitor_data(monitor, latest_checks)}
  end

  def checks(%{checks: checks}) do
    %{data: for(check <- checks, do: check_data(check))}
  end

  def checks_from_vm(%{checks: checks}) do
    %{data: Enum.map(checks, fn check ->
      %{
        status: check.status,
        response_time: check.response_time,
        status_code: check[:status_code],
        checked_at: check.checked_at
      }
    end)}
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

  defp monitor_data(%Monitor{} = monitor, latest_checks \\ %{}) do
    base = %{
      id: monitor.id,
      name: monitor.name,
      url: monitor.url,
      monitor_type: monitor.monitor_type,
      status: monitor.status,
      interval: monitor.interval,
      timeout: monitor.timeout,
      settings: monitor.settings,
      description: monitor.description,
      confirmation_threshold: monitor.confirmation_threshold,
      escalation_policy_id: monitor.escalation_policy_id,
      alert_contacts: monitor.alert_contacts || %{},
      created_at: monitor.inserted_at,
      updated_at: monitor.updated_at
    }

    base =
      case Map.get(latest_checks, to_string(monitor.id)) do
        %{} = check ->
          Map.put(base, :last_check, check)
        _ ->
          base
      end

    if monitor.uptime_percentage do
      Map.put(base, :uptime_percentage, monitor.uptime_percentage)
    else
      base
    end
  end
end
