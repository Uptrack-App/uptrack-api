defmodule UptrackWeb.Api.MonitorJSON do
  @moduledoc """
  JSON views for monitor endpoints.
  """

  alias Uptrack.Monitoring.{Monitor, MonitorCheck}

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

  def checks_from_vm(%{checks: checks} = assigns) do
    failures = Map.get(assigns, :failures, [])

    %{data: Enum.map(checks, fn check ->
      base = %{
        status: check.status,
        response_time: check.response_time,
        status_code: check[:status_code],
        checked_at: check.checked_at
      }

      # For DOWN checks, try to attach the nearest failure row (within ±30s).
      # Matching by closest timestamp because VM buckets to 30s, Postgres
      # stores microsecond precision.
      if check.status == "down" do
        case nearest_failure(failures, check.checked_at) do
          nil ->
            base

          f ->
            Map.merge(base, %{
              status_code: f.status_code || base.status_code,
              error_message: f.error_message,
              response_body: f.response_body,
              response_headers: f.response_headers
            })
        end
      else
        base
      end
    end)}
  end

  defp nearest_failure([], _), do: nil
  defp nearest_failure(failures, target) do
    failures
    |> Enum.map(fn f -> {f, abs(DateTime.diff(f.checked_at, target, :second))} end)
    |> Enum.filter(fn {_, dist} -> dist <= 30 end)
    |> case do
      [] -> nil
      list ->
        {nearest, _} = Enum.min_by(list, fn {_, dist} -> dist end)
        nearest
    end
  end

  defp check_data(%MonitorCheck{} = check) do
    %{
      id: check.id,
      monitor_id: check.monitor_id,
      status: check.status,
      response_time: check.response_time,
      status_code: check.status_code,
      error_message: check.error_message,
      response_body: check.response_body,
      response_headers: check.response_headers,
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
      reminder_interval_minutes: monitor.reminder_interval_minutes,
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
