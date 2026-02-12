defmodule Uptrack.Alerting.SlackAlertTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.SlackAlert
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}

  @moduletag :capture_log

  defp build_channel(config) do
    %AlertChannel{
      id: Uniq.UUID.uuid7(),
      name: "Test Slack Channel",
      type: "slack",
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

  describe "send_incident_alert/3" do
    test "returns error when no webhook URL configured" do
      channel = build_channel(%{})
      assert {:error, "No Slack webhook URL configured"} =
               SlackAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when webhook URL is nil" do
      channel = build_channel(%{"webhook_url" => nil})
      assert {:error, "No Slack webhook URL configured"} =
               SlackAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when webhook URL is empty" do
      channel = build_channel(%{"webhook_url" => ""})
      assert {:error, "No Slack webhook URL configured"} =
               SlackAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end
  end

  describe "send_resolution_alert/3" do
    test "returns error when no webhook URL configured" do
      channel = build_channel(%{})
      incident = %{build_incident() | resolved_at: ~U[2026-01-15 11:30:00Z], duration: 3600}

      assert {:error, "No Slack webhook URL configured"} =
               SlackAlert.send_resolution_alert(channel, incident, build_monitor())
    end
  end

  describe "send_test_alert/1" do
    test "returns error when no webhook URL configured" do
      channel = build_channel(%{})
      assert {:error, "No Slack webhook URL configured"} = SlackAlert.send_test_alert(channel)
    end

    test "returns error when webhook URL is empty" do
      channel = build_channel(%{"webhook_url" => ""})
      assert {:error, "No Slack webhook URL configured"} = SlackAlert.send_test_alert(channel)
    end
  end
end
