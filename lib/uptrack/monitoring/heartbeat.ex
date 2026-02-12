defmodule Uptrack.Monitoring.Heartbeat do
  @moduledoc """
  Heartbeat monitoring for cron jobs and batch processes.

  Heartbeat monitors are "passive" - instead of actively checking a URL,
  they wait for the monitored service to "phone home" at regular intervals.

  Each heartbeat monitor has:
  - A unique token for identification
  - An expected interval (how often the heartbeat should arrive)
  - A grace period (extra time before marking as down)

  If no heartbeat is received within (interval + grace_period), an incident is created.
  """

  import Ecto.Query

  alias Uptrack.AppRepo
  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.Monitor

  @doc """
  Generates a unique token for a heartbeat monitor.
  """
  def generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc """
  Finds a heartbeat monitor by its token.
  """
  def get_monitor_by_token(token) do
    Monitor
    |> where([m], m.monitor_type == "heartbeat")
    |> where([m], fragment("?->>'token' = ?", m.settings, ^token))
    |> where([m], m.status == "active")
    |> AppRepo.one()
  end

  @doc """
  Records a heartbeat ping from a monitored service.

  Creates a successful MonitorCheck record and updates the monitor's last_heartbeat.
  Returns the monitor for the response.
  """
  def record_heartbeat(token, metadata \\ %{}) do
    case get_monitor_by_token(token) do
      nil ->
        {:error, :not_found}

      monitor ->
        # Create a successful check record
        check_attrs = %{
          monitor_id: monitor.id,
          status: "up",
          response_time: metadata["execution_time"] || 0,
          status_code: 200,
          response_body: Jason.encode!(metadata),
          error_message: nil,
          checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        case Monitoring.create_check(check_attrs) do
          {:ok, _check} ->
            # Update monitor settings with last heartbeat time
            updated_settings =
              Map.merge(monitor.settings || %{}, %{
                "last_heartbeat" => DateTime.to_iso8601(DateTime.utc_now()),
                "last_metadata" => metadata
              })

            Monitoring.update_monitor(monitor, %{settings: updated_settings})

            # Auto-resolve any active incident
            resolve_active_incident(monitor)

            {:ok, monitor}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp resolve_active_incident(monitor) do
    # Find active incident for this monitor and resolve it
    case Monitoring.get_active_incident(monitor.id) do
      nil ->
        :ok

      incident ->
        Monitoring.resolve_incident(incident, %{
          resolution_type: :auto,
          resolution_note: "Heartbeat received - service is alive"
        })
    end
  end

  @doc """
  Checks all heartbeat monitors for missed heartbeats.

  Called periodically by an Oban job.
  Creates incidents for monitors that haven't checked in within their deadline.
  """
  def check_missed_heartbeats do
    now = DateTime.utc_now()

    Monitor
    |> where([m], m.monitor_type == "heartbeat")
    |> where([m], m.status == "active")
    |> AppRepo.all()
    |> Enum.each(fn monitor ->
      check_monitor_heartbeat(monitor, now)
    end)
  end

  defp check_monitor_heartbeat(monitor, now) do
    settings = monitor.settings || %{}
    last_heartbeat = parse_datetime(settings["last_heartbeat"])
    expected_interval = settings["expected_interval_seconds"] || 3600
    grace_period = settings["grace_period_seconds"] || 300

    deadline_seconds = expected_interval + grace_period

    if last_heartbeat && DateTime.diff(now, last_heartbeat) > deadline_seconds do
      # Check if there's already an active incident
      case Monitoring.get_active_incident(monitor.id) do
        nil ->
          # Create a new incident for missed heartbeat
          create_missed_heartbeat_incident(monitor, last_heartbeat, now)

        _incident ->
          # Incident already exists, do nothing
          :ok
      end
    end
  end

  defp create_missed_heartbeat_incident(monitor, last_heartbeat, now) do
    # Create a failed check record
    check_attrs = %{
      monitor_id: monitor.id,
      status: "down",
      response_time: 0,
      status_code: 0,
      response_body: nil,
      error_message: "Heartbeat missed - last seen #{format_duration(DateTime.diff(now, last_heartbeat))} ago",
      checked_at: now |> DateTime.truncate(:second)
    }

    case Monitoring.create_check(check_attrs) do
      {:ok, check} ->
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: monitor.organization_id,
          status: :investigating,
          cause: :heartbeat_missed,
          started_at: now,
          first_check_id: check.id
        })

      {:error, _} ->
        :error
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp format_duration(seconds) when seconds < 60, do: "#{seconds} seconds"
  defp format_duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)} minutes"
  defp format_duration(seconds), do: "#{div(seconds, 3600)} hours"

  @doc """
  Generates the heartbeat URL for a monitor.
  """
  def heartbeat_url(monitor, base_url \\ nil) do
    token = get_in(monitor.settings, ["token"])
    base = base_url || Application.get_env(:uptrack, :heartbeat_base_url, "https://uptrack.io")
    "#{base}/api/heartbeat/#{token}"
  end
end
