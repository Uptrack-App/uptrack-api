defmodule Uptrack.Alerting.TelnyxAlertTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.TelnyxAlert
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}

  @moduletag :capture_log

  defp build_channel(config) do
    %AlertChannel{
      id: Uniq.UUID.uuid7(),
      name: "Test SMS Channel",
      type: "sms",
      config: config,
      is_active: true
    }
  end

  defp build_monitor do
    %Monitor{
      id: Uniq.UUID.uuid7(),
      name: "Test Monitor",
      url: "https://example.com",
      monitor_type: "http"
    }
  end

  defp build_incident do
    %Incident{
      id: Uniq.UUID.uuid7(),
      started_at: ~U[2026-01-15 10:30:00Z],
      cause: "HTTP 500",
      status: "ongoing"
    }
  end

  describe "send_sms_incident_alert/3" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_sms_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when phone number is nil" do
      channel = build_channel(%{"phone_number" => nil})

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_sms_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when phone number is empty" do
      channel = build_channel(%{"phone_number" => ""})

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_sms_incident_alert(channel, build_incident(), build_monitor())
    end
  end

  describe "send_sms_resolution_alert/3" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})
      incident = %{build_incident() | resolved_at: ~U[2026-01-15 11:30:00Z], duration: 3600}

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_sms_resolution_alert(channel, incident, build_monitor())
    end
  end

  describe "send_phone_incident_alert/3" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_phone_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when phone number is empty" do
      channel = build_channel(%{"phone_number" => ""})

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_phone_incident_alert(channel, build_incident(), build_monitor())
    end
  end

  describe "send_phone_resolution_alert/3" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})
      incident = %{build_incident() | resolved_at: ~U[2026-01-15 11:30:00Z], duration: 3600}

      assert {:error, "No phone number configured"} =
               TelnyxAlert.send_phone_resolution_alert(channel, incident, build_monitor())
    end
  end

  describe "send_test_sms/1" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})
      assert {:error, "No phone number configured"} = TelnyxAlert.send_test_sms(channel)
    end

    test "returns error when phone number is empty" do
      channel = build_channel(%{"phone_number" => ""})
      assert {:error, "No phone number configured"} = TelnyxAlert.send_test_sms(channel)
    end
  end

  describe "send_test_call/1" do
    test "returns error when no phone number configured" do
      channel = build_channel(%{})
      assert {:error, "No phone number configured"} = TelnyxAlert.send_test_call(channel)
    end

    test "returns error when phone number is empty" do
      channel = build_channel(%{"phone_number" => ""})
      assert {:error, "No phone number configured"} = TelnyxAlert.send_test_call(channel)
    end
  end
end
