defmodule Uptrack.Monitoring.CheckWorker do
  @moduledoc """
  Worker module responsible for performing monitoring checks on URLs and services.
  """

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, MonitorCheck, Events}
  alias Uptrack.Alerting
  require Logger

  @timeout 30_000
  @user_agent "Uptrack Monitor/1.0"

  @doc """
  Performs a check for a given monitor.
  """
  def perform_check(%Monitor{} = monitor) do
    Logger.info("Performing check for monitor: #{monitor.name} (#{monitor.url})")

    start_time = System.monotonic_time(:millisecond)

    result =
      case monitor.monitor_type do
        "http" -> check_http(monitor)
        "https" -> check_http(monitor)
        "tcp" -> check_tcp(monitor)
        "ping" -> check_ping(monitor)
        "keyword" -> check_keyword(monitor)
        _ -> {:error, "Unsupported monitor type: #{monitor.monitor_type}"}
      end

    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    # Create monitor check record
    check_attrs =
      case result do
        {:ok, status_code, headers, body} ->
          %{
            monitor_id: monitor.id,
            status: "up",
            response_time: response_time,
            status_code: status_code,
            checked_at: DateTime.utc_now(),
            response_headers: headers,
            response_body: truncate_body(body)
          }

        {:error, reason} ->
          %{
            monitor_id: monitor.id,
            status: "down",
            response_time: response_time,
            checked_at: DateTime.utc_now(),
            error_message: to_string(reason)
          }
      end

    case Monitoring.create_monitor_check(check_attrs) do
      {:ok, check} ->
        handle_check_result(monitor, check)

        # Broadcast the check completion event
        Events.broadcast_check_completed(check, monitor)

        {:ok, check}

      {:error, changeset} ->
        Logger.error("Failed to create monitor check: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Performs HTTP/HTTPS check.
  """
  defp check_http(%Monitor{} = monitor) do
    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "*/*"}
    ]

    # Add custom headers from monitor settings
    headers =
      case Map.get(monitor.settings, "headers") do
        nil ->
          headers

        custom_headers when is_map(custom_headers) ->
          custom_headers
          |> Enum.reduce(headers, fn {key, value}, acc ->
            [{key, value} | acc]
          end)

        _ ->
          headers
      end

    options = [
      timeout: monitor.timeout * 1000,
      recv_timeout: monitor.timeout * 1000,
      follow_redirect: true,
      max_redirect: 5
    ]

    case Req.get(monitor.url, headers: headers, options: options) do
      {:ok, %Req.Response{status: status, headers: response_headers, body: body}} ->
        {:ok, status, Map.new(response_headers), body}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Transport error: #{reason}"}

      {:error, %Req.HTTPError{reason: reason}} ->
        {:error, "HTTP error: #{reason}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs TCP port check.
  """
  defp check_tcp(%Monitor{} = monitor) do
    uri = URI.parse(monitor.url)
    host = uri.host || monitor.url
    port = uri.port || 80

    case :gen_tcp.connect(
           String.to_charlist(host),
           port,
           [:binary, active: false],
           monitor.timeout * 1000
         ) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        {:ok, nil, %{}, ""}

      {:error, reason} ->
        {:error, "TCP connection failed: #{reason}"}
    end
  end

  @doc """
  Performs ping check using system ping command.
  """
  defp check_ping(%Monitor{} = monitor) do
    uri = URI.parse(monitor.url)
    host = uri.host || monitor.url

    case System.cmd("ping", ["-c", "1", "-W", "#{monitor.timeout * 1000}", host],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok, nil, %{}, ""}

      {output, _code} ->
        {:error, "Ping failed: #{String.trim(output)}"}
    end
  rescue
    e ->
      {:error, "Ping command error: #{Exception.message(e)}"}
  end

  @doc """
  Performs keyword check (HTTP check + keyword search).
  """
  defp check_keyword(%Monitor{} = monitor) do
    keyword = Map.get(monitor.settings, "keyword")

    if is_nil(keyword) or keyword == "" do
      {:error, "No keyword specified for keyword monitor"}
    else
      case check_http(monitor) do
        {:ok, status, headers, body} ->
          if String.contains?(body, keyword) do
            {:ok, status, headers, body}
          else
            {:error, "Keyword '#{keyword}' not found in response"}
          end

        error ->
          error
      end
    end
  end

  @doc """
  Handles the result of a monitor check and manages incidents.
  """
  defp handle_check_result(%Monitor{} = monitor, %MonitorCheck{} = check) do
    case check.status do
      "up" ->
        # If monitor is up, resolve any ongoing incidents
        case Monitoring.get_ongoing_incident(monitor.id) do
          nil ->
            :ok

          incident ->
            {:ok, resolved_incident} = Monitoring.resolve_incident(incident)
            Logger.info("Resolved incident for monitor: #{monitor.name}")
            Events.broadcast_incident_resolved(resolved_incident, monitor)

            # Send resolution alerts
            Task.start(fn ->
              Alerting.send_resolution_alerts(resolved_incident, monitor)
            end)
        end

      "down" ->
        # If monitor is down, create or update incident
        case Monitoring.get_ongoing_incident(monitor.id) do
          nil ->
            # Create new incident
            incident_attrs = %{
              monitor_id: monitor.id,
              first_check_id: check.id,
              cause: check.error_message
            }

            case Monitoring.create_incident(incident_attrs) do
              {:ok, incident} ->
                Logger.warning("Created incident for monitor: #{monitor.name}")
                Events.broadcast_incident_created(incident, monitor)

                # Send alerts for the new incident
                Task.start(fn ->
                  Alerting.send_incident_alerts(incident, monitor)
                end)

              {:error, changeset} ->
                Logger.error("Failed to create incident: #{inspect(changeset.errors)}")
            end

          incident ->
            # Update existing incident with latest check
            Logger.info("Ongoing incident for monitor: #{monitor.name}")
        end
    end
  end

  @doc """
  Truncates response body to prevent storing very large responses.
  """
  defp truncate_body(body) when is_binary(body) do
    max_length = 10_000

    if String.length(body) > max_length do
      String.slice(body, 0, max_length) <> "... [truncated]"
    else
      body
    end
  end

  defp truncate_body(_), do: nil
end
