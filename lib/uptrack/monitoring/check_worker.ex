defmodule Uptrack.Monitoring.CheckWorker do
  @moduledoc """
  Worker module responsible for performing monitoring checks on URLs and services.

  ## Responsibilities

  This module persists check results, manages the per-monitor
  `consecutive_failures` counter, resolves ongoing incidents on successful
  checks, and runs response-time degradation detection.

  It deliberately **does not** create incidents or dispatch initial
  "incident created" alerts on the DOWN path. That responsibility belongs
  to `Uptrack.Monitoring.MonitorProcess`, which owns the cross-region
  consensus decision. See `Uptrack.Monitoring` moduledoc for the full
  ownership contract.
  """

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, MonitorCheck, Events}
  alias Uptrack.Alerting
  alias Uptrack.Maintenance
  alias Uptrack.Metrics.Writer, as: MetricsWriter
  require Logger
  require Record

  # Extract OTP certificate record definitions for safe field access
  Record.defrecordp(:otp_cert, :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(:otp_tbs, :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(:validity, :Validity,
    Record.extract(:Validity, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )


  @doc """
  Executes only the raw network check (no DB write, no alerts).
  Used by CheckExecutor for the GenServer pipeline.
  Returns {:ok, status_code, headers, body} or {:error, reason}.
  """
  def execute_raw_check(%Monitor{} = monitor) do
    case monitor.monitor_type do
      "http" -> check_http(monitor)
      "https" -> check_http(monitor)
      "tcp" -> check_tcp(monitor)
      "ping" -> check_ping(monitor)
      "keyword" -> check_keyword(monitor)
      "ssl" -> check_ssl(monitor)
      "dns" -> check_dns(monitor)
      "heartbeat" -> {:ok, nil, %{}, ""}
      _ -> {:error, "Unsupported monitor type: #{monitor.monitor_type}"}
    end
  end

  @doc """
  Performs a full check for a given monitor (check + DB write + alerts).
  Used by Oban CheckWorker.
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
        "dns" -> check_dns(monitor)
        "heartbeat" -> {:ok, nil, %{}, ""}  # Heartbeat is passive, no active check
        _ -> {:error, "Unsupported monitor type: #{monitor.monitor_type}"}
      end

    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time

    # Create monitor check record
    check_attrs =
      case result do
        {:ok, status_code, headers, body} ->
          expected = Map.get(monitor.settings, "expected_status_code")
          assertions = Map.get(monitor.settings, "assertions", [])

          base = %{
            monitor_id: monitor.id,
            response_time: response_time,
            status_code: status_code,
            checked_at: DateTime.utc_now(),
            response_headers: headers,
            response_body: truncate_body(body)
          }

          cond do
            expected && status_code != expected ->
              Map.merge(base, %{status: "down", error_message: "Expected status #{expected}, got #{status_code}"})

            assertions != [] ->
              case Uptrack.Monitoring.Assertions.evaluate(assertions, status_code, headers, body) do
                :ok -> Map.put(base, :status, "up")
                {:error, msg} -> Map.merge(base, %{status: "down", error_message: "Assertion failed: #{msg}"})
              end

            true ->
              Map.put(base, :status, "up")
          end

        {:error, reason} ->
          %{
            monitor_id: monitor.id,
            status: "down",
            response_time: response_time,
            checked_at: DateTime.utc_now(),
            error_message: to_string(reason)
          }
      end

    check = struct!(MonitorCheck, check_attrs)

    handle_check_result(monitor, check)
    Events.broadcast_check_completed(check, monitor)
    MetricsWriter.write_check_result(monitor, check)

    {:ok, check}
  end

  # Performs HTTP/HTTPS check.
  defp check_http(%Monitor{} = monitor) do
    headers =
      case Map.get(monitor.settings, "headers") do
        nil -> []
        custom_headers when is_map(custom_headers) -> Enum.to_list(custom_headers)
        _ -> []
      end

    method = Map.get(monitor.settings, "method", "GET")
    timeout = monitor.timeout * 1000

    body =
      case {method, Map.get(monitor.settings, "body")} do
        {m, b} when m in ["POST", "PUT", "PATCH", "post", "put", "patch"]
                     and is_binary(b) and b != "" -> b
        _ -> nil
      end

    Uptrack.Monitoring.HttpCheck.check(monitor.url,
      method: method,
      headers: headers,
      body: body,
      timeout: timeout
    )
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
    {host, port} = parse_host_port(monitor.url, 443)
    settings = monitor.settings || %{}
    expiry_threshold = settings["expiry_threshold"] || settings["warn_days_before_expiry"] || 30

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

            cond do
              days_remaining < 0 ->
                {:error, "SSL certificate expired on #{cert_info.not_after}"}

              days_remaining <= expiry_threshold ->
                {:error, "SSL certificate expires in #{days_remaining} days"}

              true ->
                metadata = %{
                  "ssl_expiry" => cert_info.not_after,
                  "ssl_issuer" => cert_info.issuer,
                  "ssl_subject" => cert_info.subject,
                  "ssl_days_remaining" => days_remaining
                }
                {:ok, nil, metadata, Jason.encode!(cert_info)}
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

  # Performs DNS record check.
  defp check_dns(%Monitor{} = monitor) do
    settings = monitor.settings || %{}
    record_type = settings["dns_record_type"] || "A"
    expected = settings["dns_expected_value"] || ""
    dns_server = settings["dns_server"]
    host = monitor.url |> String.trim()

    type_atom =
      case String.upcase(record_type) do
        "A" -> :a
        "AAAA" -> :aaaa
        "CNAME" -> :cname
        "MX" -> :mx
        "TXT" -> :txt
        "NS" -> :ns
        "SOA" -> :soa
        _ -> :a
      end

    nameserver_opts =
      case dns_server do
        nil -> []
        "" -> []
        server ->
          case :inet.parse_address(String.to_charlist(server)) do
            {:ok, ip} -> [nameservers: [{ip, 53}]]
            _ -> []
          end
      end

    opts = [{:timeout, monitor.timeout * 1000} | nameserver_opts]

    case :inet_res.resolve(String.to_charlist(host), :in, type_atom, opts) do
      {:ok, msg} ->
        answers = :inet_dns.msg(msg, :anlist)
        values = Enum.map(answers, &format_dns_record(type_atom, &1))

        if expected == "" do
          # No expected value — just check we got any result
          if values == [] do
            {:error, "No #{record_type} records found for #{host}"}
          else
            {:ok, nil, %{"dns_records" => values}, Enum.join(values, "\n")}
          end
        else
          if dns_matches?(type_atom, values, expected) do
            {:ok, nil, %{"dns_records" => values}, Enum.join(values, "\n")}
          else
            {:error, "DNS #{record_type} mismatch: expected #{expected}, got #{Enum.join(values, ", ")}"}
          end
        end

      {:error, :timeout} ->
        {:error, "DNS query timeout"}

      {:error, :nxdomain} ->
        {:error, "DNS domain not found (NXDOMAIN)"}

      {:error, reason} ->
        {:error, "DNS query failed: #{inspect(reason)}"}
    end
  rescue
    e ->
      {:error, "DNS check error: #{Exception.message(e)}"}
  end

  defp format_dns_record(:a, rr) do
    data = :inet_dns.rr(rr, :data)
    data |> Tuple.to_list() |> Enum.join(".")
  end

  defp format_dns_record(:aaaa, rr) do
    data = :inet_dns.rr(rr, :data)
    data |> Tuple.to_list() |> Enum.map(&Integer.to_string(&1, 16)) |> Enum.join(":")
  end

  defp format_dns_record(:cname, rr) do
    :inet_dns.rr(rr, :data) |> to_string()
  end

  defp format_dns_record(:mx, rr) do
    {priority, exchange} = :inet_dns.rr(rr, :data)
    "#{priority} #{to_string(exchange)}"
  end

  defp format_dns_record(:txt, rr) do
    :inet_dns.rr(rr, :data) |> Enum.map(&to_string/1) |> Enum.join("")
  end

  defp format_dns_record(:ns, rr) do
    :inet_dns.rr(rr, :data) |> to_string()
  end

  defp format_dns_record(:soa, rr) do
    {mname, rname, serial, _, _, _, _} = :inet_dns.rr(rr, :data)
    "#{to_string(mname)} #{to_string(rname)} #{serial}"
  end

  defp format_dns_record(_, rr) do
    inspect(:inet_dns.rr(rr, :data))
  end

  defp dns_matches?(:txt, values, expected) do
    # For TXT, check if any record contains the expected substring
    Enum.any?(values, &String.contains?(&1, expected))
  end

  defp dns_matches?(_, values, expected) do
    # For other types, check exact match against any record
    expected_trimmed = String.trim(expected)
    Enum.any?(values, fn v -> String.trim(v) == expected_trimmed end)
  end

  defp parse_certificate(der_cert) do
    cert = :public_key.pkix_decode_cert(der_cert, :otp)
    tbs = otp_cert(cert, :tbsCertificate)
    val = otp_tbs(tbs, :validity)

    not_before = parse_cert_time(validity(val, :notBefore))
    not_after = parse_cert_time(validity(val, :notAfter))
    subject = extract_cn(otp_tbs(tbs, :subject))
    issuer = extract_cn(otp_tbs(tbs, :issuer))

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
        # Reset consecutive failure counter on success
        Monitoring.reset_consecutive_failures(monitor.id)

        # If monitor is up, resolve every ongoing incident (duplicates can
        # accumulate across restarts or races — resolve them all so the
        # dashboard reflects reality)
        case Monitoring.resolve_all_ongoing_incidents(monitor.id) do
          {:ok, []} ->
            :ok

          {:ok, [primary | _] = resolved_all} ->
            Logger.info(
              "Resolved #{length(resolved_all)} incident(s) for monitor: #{monitor.name}"
            )

            Enum.each(resolved_all, &Events.broadcast_incident_resolved(&1, monitor))

            Task.start(fn ->
              Alerting.send_resolution_alerts(primary, monitor)
              Alerting.notify_subscribers_resolution(primary, monitor)
            end)

          {:error, reason} ->
            Logger.error(
              "Failed resolving ongoing incidents for #{monitor.name}: #{inspect(reason)}"
            )
        end

        # Check for response time degradation
        check_degradation(monitor, check)

      "down" ->
        # NOTE: CheckWorker no longer creates incidents or dispatches down alerts.
        # That responsibility is owned by Uptrack.Monitoring.MonitorProcess, which
        # has the cross-region consensus view. We still maintain the counter and
        # schedule confirmation checks so metrics/scheduling stay correct.
        case Monitoring.get_ongoing_incident(monitor.id) do
          nil ->
            Monitoring.increment_consecutive_failures(monitor.id)
            current_failures = Monitoring.get_consecutive_failures(monitor.id)

            if current_failures < monitor.confirmation_threshold do
              Logger.info(
                "Check failed (#{current_failures}/#{monitor.confirmation_threshold}), scheduling confirmation for: #{monitor.name}"
              )

              schedule_confirmation_check(monitor)
            else
              Logger.debug(
                "Check failed at threshold (#{current_failures}/#{monitor.confirmation_threshold}) for #{monitor.name} — MonitorProcess owns alert dispatch"
              )
            end

          _incident ->
            Logger.debug("Ongoing incident already exists for monitor: #{monitor.name}")
        end
    end
  end

  defp schedule_confirmation_check(monitor) do
    %{monitor_id: monitor.id}
    |> Uptrack.Monitoring.ConfirmationCheckWorker.new(
      scheduled_at: DateTime.add(DateTime.utc_now(), 10, :second)
    )
    |> Oban.insert()
  end

  # Truncates response body to prevent storing very large responses.
  # Default 1KB — sufficient for assertions, prevents scraping abuse.
  defp truncate_body(body, max_length \\ 1_000)
  defp truncate_body(nil, _max_length), do: nil
  defp truncate_body(body, max_length) when is_binary(body) do
    if String.length(body) > max_length do
      String.slice(body, 0, max_length) <> "... [truncated]"
    else
      body
    end
  end
  defp truncate_body(_, _max_length), do: nil


  # Response time degradation detection.
  # If the monitor has a response_time_threshold in settings, and the check
  # exceeds it, create a "degraded" incident.
  @doc "Checks if response time exceeds threshold and creates degradation incident."
  def check_degradation(%Monitor{} = monitor, %MonitorCheck{} = check) do
    threshold = get_in(monitor.settings || %{}, ["response_time_threshold"])

    cond do
      is_nil(threshold) or is_nil(check.response_time) ->
        :ok

      check.response_time > threshold ->
        cond do
          Maintenance.under_maintenance?(monitor.id, monitor.organization_id) ->
            Logger.info(
              "Monitor #{monitor.name} degraded during maintenance — suppressing degradation alert"
            )

          Monitoring.get_ongoing_incident(monitor.id) != nil ->
            :ok

          true ->
            Logger.info(
              "Monitor #{monitor.name} degraded: #{check.response_time}ms > #{threshold}ms threshold"
            )

            incident_attrs = %{
              monitor_id: monitor.id,
              organization_id: monitor.organization_id,
              status: "investigating",
              cause:
                "Response time degradation: #{check.response_time}ms (threshold: #{threshold}ms)",
              started_at: DateTime.utc_now() |> DateTime.truncate(:second)
            }

            case Monitoring.create_incident(incident_attrs) do
              {:ok, incident} ->
                Events.broadcast_incident_created(incident, monitor)

                Task.start(fn ->
                  Alerting.send_incident_alerts(incident, monitor)
                end)

              {:error, _} ->
                :ok
            end
        end

      true ->
        :ok
    end
  end
end
