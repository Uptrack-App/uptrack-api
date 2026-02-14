defmodule Uptrack.Monitoring.CheckWorker do
  @moduledoc """
  Worker module responsible for performing monitoring checks on URLs and services.
  """

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, MonitorCheck, Events}
  alias Uptrack.Alerting
  alias Uptrack.Metrics.Writer, as: MetricsWriter
  require Logger

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
        "ssl" -> check_ssl(monitor)
        "heartbeat" -> {:ok, nil, %{}, ""}  # Heartbeat is passive, no active check
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

        # Publish metrics to VictoriaMetrics
        MetricsWriter.write_check_result(monitor, check)

        {:ok, check}

      {:error, changeset} ->
        Logger.error("Failed to create monitor check: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # Performs HTTP/HTTPS check.
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

    case Req.get(monitor.url,
           headers: headers,
           connect_options: [timeout: monitor.timeout * 1000],
           receive_timeout: monitor.timeout * 1000,
           redirect: true,
           max_redirects: 5,
           retry: false
         ) do
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

  # Performs TCP port check.
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

  # Performs ping check using system ping command.
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

  # Performs keyword check (HTTP check + keyword search).
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

  # Performs SSL certificate check.
  defp check_ssl(%Monitor{} = monitor) do
    # Parse host and port from URL
    {host, port} = parse_host_port(monitor.url, 443)
    settings = monitor.settings || %{}
    warn_days = settings["warn_days_before_expiry"] || 30

    case :ssl.connect(String.to_charlist(host), port, [
           verify: :verify_none,
           depth: 10,
           cacerts: :public_key.cacerts_get()
         ], monitor.timeout * 1000) do
      {:ok, ssl_socket} ->
        case :ssl.peercert(ssl_socket) do
          {:ok, der_cert} ->
            :ssl.close(ssl_socket)
            cert_info = parse_certificate(der_cert)

            days_remaining = cert_info.days_until_expiry

            if days_remaining < 0 do
              {:error, "SSL certificate expired #{abs(days_remaining)} days ago"}
            else if days_remaining < warn_days do
              # Certificate expiring soon - still return OK but with warning
              metadata = %{
                "ssl_warning" => "Certificate expires in #{days_remaining} days",
                "ssl_expiry" => cert_info.not_after,
                "ssl_issuer" => cert_info.issuer,
                "ssl_subject" => cert_info.subject,
                "ssl_days_remaining" => days_remaining
              }
              {:ok, 200, metadata, Jason.encode!(cert_info)}
            else
              metadata = %{
                "ssl_expiry" => cert_info.not_after,
                "ssl_issuer" => cert_info.issuer,
                "ssl_subject" => cert_info.subject,
                "ssl_days_remaining" => days_remaining
              }
              {:ok, 200, metadata, Jason.encode!(cert_info)}
            end
            end

          {:error, reason} ->
            :ssl.close(ssl_socket)
            {:error, "Failed to get certificate: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "SSL connection failed: #{inspect(reason)}"}
    end
  rescue
    e ->
      {:error, "SSL check error: #{Exception.message(e)}"}
  end

  defp parse_certificate(der_cert) do
    # Decode the certificate
    otp_cert = :public_key.pkix_decode_cert(der_cert, :otp)
    tbs = elem(otp_cert, 2)

    # Extract validity period
    validity = elem(tbs, 5)
    not_before = parse_cert_time(elem(validity, 1))
    not_after = parse_cert_time(elem(validity, 2))

    # Extract subject and issuer
    subject = extract_cn(elem(tbs, 6))
    issuer = extract_cn(elem(tbs, 4))

    # Calculate days until expiry
    now = DateTime.utc_now()
    days_until_expiry = DateTime.diff(not_after, now, :day)

    %{
      subject: subject,
      issuer: issuer,
      not_before: DateTime.to_iso8601(not_before),
      not_after: DateTime.to_iso8601(not_after),
      days_until_expiry: days_until_expiry,
      is_valid: days_until_expiry > 0
    }
  end

  defp parse_cert_time({:utcTime, time_str}) do
    # UTCTime format: YYMMDDHHMMSSZ
    <<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2),
      hh::binary-size(2), mi::binary-size(2), ss::binary-size(2), "Z">> = to_string(time_str)

    year = String.to_integer(yy)
    year = if year >= 50, do: 1900 + year, else: 2000 + year

    {:ok, dt} = DateTime.new(
      Date.new!(year, String.to_integer(mm), String.to_integer(dd)),
      Time.new!(String.to_integer(hh), String.to_integer(mi), String.to_integer(ss))
    )
    dt
  end

  defp parse_cert_time({:generalTime, time_str}) do
    # GeneralizedTime format: YYYYMMDDHHMMSSZ
    <<yyyy::binary-size(4), mm::binary-size(2), dd::binary-size(2),
      hh::binary-size(2), mi::binary-size(2), ss::binary-size(2), "Z">> = to_string(time_str)

    {:ok, dt} = DateTime.new(
      Date.new!(String.to_integer(yyyy), String.to_integer(mm), String.to_integer(dd)),
      Time.new!(String.to_integer(hh), String.to_integer(mi), String.to_integer(ss))
    )
    dt
  end

  defp extract_cn(rdn_sequence) do
    # RDN sequence contains lists of attribute-value pairs
    # We want to find the CN (Common Name)
    {:rdnSequence, rdns} = rdn_sequence

    cn = Enum.find_value(rdns, fn rdn ->
      Enum.find_value(rdn, fn
        {:AttributeTypeAndValue, {2, 5, 4, 3}, value} ->
          extract_string_value(value)
        _ ->
          nil
      end)
    end)

    cn || "Unknown"
  end

  defp extract_string_value({:utf8String, value}), do: to_string(value)
  defp extract_string_value({:printableString, value}), do: to_string(value)
  defp extract_string_value({:teletexString, value}), do: to_string(value)
  defp extract_string_value(value) when is_binary(value), do: value
  defp extract_string_value(value) when is_list(value), do: to_string(value)
  defp extract_string_value(_), do: "Unknown"

  defp parse_host_port(url, default_port) do
    cond do
      # Full URL with scheme
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://") ->
        uri = URI.parse(url)
        {uri.host, uri.port || default_port}

      # host:port format
      String.match?(url, ~r/^[^:]+:\d+$/) ->
        [host, port_str] = String.split(url, ":")
        {host, String.to_integer(port_str)}

      # Just hostname
      true ->
        {url, default_port}
    end
  end

  # Handles the result of a monitor check and manages incidents.
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
              Alerting.notify_subscribers_resolution(resolved_incident, monitor)
            end)
        end

      "down" ->
        # If monitor is down, create or update incident
        case Monitoring.get_ongoing_incident(monitor.id) do
          nil ->
            # Create new incident
            incident_attrs = %{
              monitor_id: monitor.id,
              organization_id: monitor.organization_id,
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
                  Alerting.notify_subscribers_incident(incident, monitor)
                end)

              {:error, changeset} ->
                Logger.error("Failed to create incident: #{inspect(changeset.errors)}")
            end

          _incident ->
            # Update existing incident with latest check
            Logger.info("Ongoing incident for monitor: #{monitor.name}")
        end
    end
  end

  # Truncates response body to prevent storing very large responses.
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
