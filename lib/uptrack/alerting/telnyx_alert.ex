defmodule Uptrack.Alerting.TelnyxAlert do
  @moduledoc """
  Handles SMS and phone call alerts via Telnyx.

  SMS uses alphanumeric sender ID "Uptrack" by default (free, works in EU/AU/Africa/Asia).
  For US/Canada where alphanumeric is not supported, set TELNYX_PHONE_NUMBER.
  Voice calls always require TELNYX_PHONE_NUMBER and TELNYX_CONNECTION_ID.

  Environment variables:
  - TELNYX_API_KEY (required)
  - TELNYX_PHONE_NUMBER (required for voice, optional for SMS — used for US/Canada)
  - TELNYX_CONNECTION_ID (required for voice calls via TeXML)
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @telnyx_messaging_url "https://api.telnyx.com/v2/messages"
  @telnyx_texml_url "https://api.telnyx.com/v2/texml/calls"
  @alphanumeric_sender_id "Uptrack"
  # US (+1) and Canada (+1) don't support alphanumeric sender IDs
  @phone_number_required_prefixes ["+1"]

  @doc """
  Sends an SMS incident alert.
  """
  def send_sms_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      message = build_incident_sms(incident, monitor)
      send_sms(phone_number, message)
    end
  end

  @doc """
  Sends an SMS resolution alert.
  """
  def send_sms_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      message = build_resolution_sms(incident, monitor)
      send_sms(phone_number, message)
    end
  end

  @doc """
  Makes a phone call for critical incident alerts.
  """
  def send_phone_incident_alert(%AlertChannel{} = channel, %Incident{} = incident, %Monitor{} = monitor) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      texml = build_incident_texml(incident, monitor)
      make_call(phone_number, texml)
    end
  end

  @doc """
  Makes a phone call for resolution alerts.
  """
  def send_phone_resolution_alert(
        %AlertChannel{} = channel,
        %Incident{} = incident,
        %Monitor{} = monitor
      ) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      texml = build_resolution_texml(incident, monitor)
      make_call(phone_number, texml)
    end
  end

  @doc """
  Sends a test SMS.
  """
  def send_test_sms(%AlertChannel{} = channel) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      message = "Uptrack Test: Your SMS integration is working correctly!"
      send_sms(phone_number, message)
    end
  end

  @doc """
  Makes a test phone call.
  """
  def send_test_call(%AlertChannel{} = channel) do
    phone_number = channel.config["phone_number"]

    if is_nil(phone_number) or phone_number == "" do
      {:error, "No phone number configured"}
    else
      texml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Response>
        <Say>This is a test call from Uptrack. Your phone integration is working correctly. Goodbye.</Say>
      </Response>
      """

      make_call(phone_number, texml)
    end
  end

  defp build_incident_sms(incident, monitor) do
    cause = incident.cause || "Unknown"
    # Keep SMS short - 160 char limit for single segment
    "ALERT: #{monitor.name} is DOWN\n#{monitor.url}\nCause: #{String.slice(cause, 0..50)}"
  end

  defp build_resolution_sms(incident, monitor) do
    duration = format_duration(incident.duration)
    "RESOLVED: #{monitor.name} is UP\nDowntime: #{duration}"
  end

  defp build_incident_texml(incident, monitor) do
    cause = incident.cause || "unknown cause"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
      <Say>
        Alert! Your monitor #{escape_xml(monitor.name)} is down.
        The URL #{escape_xml(monitor.url)} is not responding.
        Cause: #{escape_xml(cause)}.
        Please check your dashboard for more details.
      </Say>
      <Pause length="1"/>
      <Say>
        This message will repeat.
      </Say>
      <Pause length="2"/>
      <Say>
        Alert! #{escape_xml(monitor.name)} is down.
      </Say>
    </Response>
    """
  end

  defp build_resolution_texml(incident, monitor) do
    duration = format_duration(incident.duration)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
      <Say>
        Good news! Your monitor #{escape_xml(monitor.name)} is back up.
        Total downtime was #{duration}.
      </Say>
    </Response>
    """
  end

  defp send_sms(to_number, message) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, from} <- get_sms_sender(to_number) do
      case Req.post(@telnyx_messaging_url,
             headers: [{"authorization", "Bearer #{api_key}"}],
             json: %{
               from: from,
               to: to_number,
               text: message
             }
           ) do
        {:ok, %{status: status, body: %{"data" => %{"id" => id}}}} when status in [200, 201] ->
          Logger.info("SMS sent successfully via Telnyx: #{id}")
          {:ok, id}

        {:ok, %{status: status, body: body}} ->
          error_msg = get_in(body, ["errors", Access.at(0), "detail"]) || "Unknown error"
          Logger.error("Telnyx SMS failed: #{status} - #{error_msg}")
          {:error, "HTTP #{status}: #{error_msg}"}

        {:error, reason} ->
          Logger.error("Failed to send SMS via Telnyx: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # US/Canada require a phone number; everywhere else uses alphanumeric sender ID
  defp get_sms_sender(to_number) do
    if requires_phone_number?(to_number) do
      case get_from_number() do
        {:ok, _} = result -> result
        {:error, _} -> {:error, "TELNYX_PHONE_NUMBER required for US/Canada SMS"}
      end
    else
      {:ok, @alphanumeric_sender_id}
    end
  end

  defp requires_phone_number?(to_number) do
    Enum.any?(@phone_number_required_prefixes, &String.starts_with?(to_number, &1))
  end

  defp make_call(to_number, texml) do
    with {:ok, api_key} <- get_api_key(),
         {:ok, from_number} <- get_from_number(),
         {:ok, connection_id} <- get_connection_id() do
      url = "#{@telnyx_texml_url}/#{connection_id}"

      case Req.post(url,
             headers: [
               {"authorization", "Bearer #{api_key}"},
               {"content-type", "application/x-www-form-urlencoded"}
             ],
             body:
               URI.encode_query(%{
                 "To" => to_number,
                 "From" => from_number,
                 "Telnyx-TeXML-Body" => texml
               })
           ) do
        {:ok, %{status: status, body: body}} when status in [200, 201] ->
          call_sid = if is_map(body), do: body["call_sid"], else: "ok"
          Logger.info("Call initiated successfully via Telnyx: #{call_sid}")
          {:ok, call_sid}

        {:ok, %{status: status, body: body}} ->
          error_msg =
            if is_map(body),
              do: get_in(body, ["errors", Access.at(0), "detail"]) || inspect(body),
              else: inspect(body)

          Logger.error("Telnyx call failed: #{status} - #{error_msg}")
          {:error, "HTTP #{status}: #{error_msg}"}

        {:error, reason} ->
          Logger.error("Failed to initiate call via Telnyx: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_api_key do
    case Application.get_env(:uptrack, :telnyx_api_key) ||
           System.get_env("TELNYX_API_KEY") do
      nil -> {:error, "TELNYX_API_KEY not configured"}
      key -> {:ok, key}
    end
  end

  defp get_from_number do
    case Application.get_env(:uptrack, :telnyx_phone_number) ||
           System.get_env("TELNYX_PHONE_NUMBER") do
      nil -> {:error, "TELNYX_PHONE_NUMBER not configured (required for US/Canada SMS and voice)"}
      "" -> {:error, "TELNYX_PHONE_NUMBER not configured (required for US/Canada SMS and voice)"}
      number -> {:ok, number}
    end
  end

  defp get_connection_id do
    case Application.get_env(:uptrack, :telnyx_connection_id) ||
           System.get_env("TELNYX_CONNECTION_ID") do
      nil -> {:error, "TELNYX_CONNECTION_ID not configured"}
      id -> {:ok, id}
    end
  end

  defp escape_xml(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp escape_xml(_), do: ""

  defp format_duration(nil), do: "unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds} seconds"
      seconds < 3600 -> "#{div(seconds, 60)} minutes"
      true -> "#{div(seconds, 3600)} hours and #{div(rem(seconds, 3600), 60)} minutes"
    end
  end
end
