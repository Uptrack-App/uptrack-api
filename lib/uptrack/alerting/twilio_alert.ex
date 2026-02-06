defmodule Uptrack.Alerting.TwilioAlert do
  @moduledoc """
  Handles SMS and phone call alerts via Twilio.

  Requires environment variables:
  - TWILIO_ACCOUNT_SID
  - TWILIO_AUTH_TOKEN
  - TWILIO_PHONE_NUMBER (the "from" number)
  """

  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  require Logger

  @twilio_api_base "https://api.twilio.com/2010-04-01"

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
      twiml = build_incident_twiml(incident, monitor)
      make_call(phone_number, twiml)
    end
  end

  @doc """
  Makes a phone call for resolution (typically not used, but available).
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
      twiml = build_resolution_twiml(incident, monitor)
      make_call(phone_number, twiml)
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
      twiml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Response>
        <Say voice="alice">This is a test call from Uptrack. Your phone integration is working correctly. Goodbye.</Say>
      </Response>
      """

      make_call(phone_number, twiml)
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

  defp build_incident_twiml(incident, monitor) do
    cause = incident.cause || "unknown cause"

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
      <Say voice="alice">
        Alert! Your monitor #{escape_xml(monitor.name)} is down.
        The URL #{escape_xml(monitor.url)} is not responding.
        Cause: #{escape_xml(cause)}.
        Please check your dashboard for more details.
      </Say>
      <Pause length="1"/>
      <Say voice="alice">
        This message will repeat.
      </Say>
      <Pause length="2"/>
      <Say voice="alice">
        Alert! #{escape_xml(monitor.name)} is down.
      </Say>
    </Response>
    """
  end

  defp build_resolution_twiml(incident, monitor) do
    duration = format_duration(incident.duration)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <Response>
      <Say voice="alice">
        Good news! Your monitor #{escape_xml(monitor.name)} is back up.
        Total downtime was #{duration}.
      </Say>
    </Response>
    """
  end

  defp send_sms(to_number, message) do
    with {:ok, account_sid} <- get_twilio_account_sid(),
         {:ok, auth_token} <- get_twilio_auth_token(),
         {:ok, from_number} <- get_twilio_from_number() do
      url = "#{@twilio_api_base}/Accounts/#{account_sid}/Messages.json"

      body =
        URI.encode_query(%{
          "To" => to_number,
          "From" => from_number,
          "Body" => message
        })

      auth = Base.encode64("#{account_sid}:#{auth_token}")

      headers = [
        {"Authorization", "Basic #{auth}"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 201, body: %{"sid" => sid}}} ->
          Logger.info("SMS sent successfully: #{sid}")
          {:ok, sid}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Twilio SMS failed: #{status} - #{inspect(body)}")
          {:error, "HTTP #{status}: #{body["message"] || "Unknown error"}"}

        {:error, reason} ->
          Logger.error("Failed to send SMS: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp make_call(to_number, twiml) do
    with {:ok, account_sid} <- get_twilio_account_sid(),
         {:ok, auth_token} <- get_twilio_auth_token(),
         {:ok, from_number} <- get_twilio_from_number() do
      url = "#{@twilio_api_base}/Accounts/#{account_sid}/Calls.json"

      body =
        URI.encode_query(%{
          "To" => to_number,
          "From" => from_number,
          "Twiml" => twiml
        })

      auth = Base.encode64("#{account_sid}:#{auth_token}")

      headers = [
        {"Authorization", "Basic #{auth}"},
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      case Req.post(url, body: body, headers: headers) do
        {:ok, %{status: 201, body: %{"sid" => sid}}} ->
          Logger.info("Call initiated successfully: #{sid}")
          {:ok, sid}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Twilio call failed: #{status} - #{inspect(body)}")
          {:error, "HTTP #{status}: #{body["message"] || "Unknown error"}"}

        {:error, reason} ->
          Logger.error("Failed to initiate call: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp get_twilio_account_sid do
    case Application.get_env(:uptrack, :twilio_account_sid) ||
           System.get_env("TWILIO_ACCOUNT_SID") do
      nil -> {:error, "TWILIO_ACCOUNT_SID not configured"}
      sid -> {:ok, sid}
    end
  end

  defp get_twilio_auth_token do
    case Application.get_env(:uptrack, :twilio_auth_token) ||
           System.get_env("TWILIO_AUTH_TOKEN") do
      nil -> {:error, "TWILIO_AUTH_TOKEN not configured"}
      token -> {:ok, token}
    end
  end

  defp get_twilio_from_number do
    case Application.get_env(:uptrack, :twilio_phone_number) ||
           System.get_env("TWILIO_PHONE_NUMBER") do
      nil -> {:error, "TWILIO_PHONE_NUMBER not configured"}
      number -> {:ok, number}
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
