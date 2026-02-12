defmodule Uptrack.Alerting.TelegramAlertTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.TelegramAlert
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}

  @moduletag :capture_log

  defp build_channel(config) do
    %AlertChannel{
      id: Uniq.UUID.uuid7(),
      name: "Test Telegram Channel",
      type: "telegram",
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
    test "returns error when no bot token configured" do
      channel = build_channel(%{"chat_id" => "12345"})
      assert {:error, "No Telegram bot token configured"} =
               TelegramAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when bot token is empty" do
      channel = build_channel(%{"bot_token" => "", "chat_id" => "12345"})
      assert {:error, "No Telegram bot token configured"} =
               TelegramAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end

    test "returns error when no chat ID configured" do
      channel = build_channel(%{"bot_token" => "123:ABC"})
      assert {:error, "No Telegram chat ID configured"} =
               TelegramAlert.send_incident_alert(channel, build_incident(), build_monitor())
    end
  end

  describe "send_resolution_alert/3" do
    test "returns error when config is missing" do
      channel = build_channel(%{})
      incident = %{build_incident() | resolved_at: ~U[2026-01-15 11:30:00Z], duration: 3600}

      assert {:error, "No Telegram bot token configured"} =
               TelegramAlert.send_resolution_alert(channel, incident, build_monitor())
    end
  end

  describe "send_test_alert/1" do
    test "returns error when no bot token configured" do
      channel = build_channel(%{})
      assert {:error, "No Telegram bot token configured"} = TelegramAlert.send_test_alert(channel)
    end

    test "returns error when no chat ID configured" do
      channel = build_channel(%{"bot_token" => "123:ABC"})
      assert {:error, "No Telegram chat ID configured"} = TelegramAlert.send_test_alert(channel)
    end
  end
end
