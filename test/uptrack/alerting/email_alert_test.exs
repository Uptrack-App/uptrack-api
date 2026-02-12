defmodule Uptrack.Alerting.EmailAlertTest do
  use Uptrack.DataCase

  import Swoosh.TestAssertions

  alias Uptrack.Alerting.EmailAlert
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}
  alias Uptrack.Accounts.User

  @moduletag :capture_log

  defp build_channel(config \\ %{}) do
    %AlertChannel{
      id: Uniq.UUID.uuid7(),
      name: "Test Email Channel",
      type: "email",
      config: Map.merge(%{"email" => "test@example.com"}, config),
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

  defp build_incident(attrs \\ %{}) do
    Map.merge(
      %Incident{
        id: Uniq.UUID.uuid7(),
        started_at: ~U[2026-01-15 10:30:00Z],
        cause: "HTTP 500",
        status: "ongoing"
      },
      attrs
    )
  end

  defp build_user(prefs) do
    %User{
      id: Uniq.UUID.uuid7(),
      email: "user@example.com",
      name: "Test User",
      notification_preferences: prefs
    }
  end

  describe "send_incident_alert/4" do
    test "sends email with correct subject and recipient" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident()

      assert {:ok, "test@example.com"} =
               EmailAlert.send_incident_alert(channel, incident, monitor)

      assert_email_sent(
        to: [{"", "test@example.com"}],
        subject: "🚨 Alert: Test Monitor is DOWN"
      )
    end

    test "returns error when no email configured" do
      channel = build_channel(%{"email" => nil})
      monitor = build_monitor()
      incident = build_incident()

      assert {:error, "No email address configured"} =
               EmailAlert.send_incident_alert(channel, incident, monitor)
    end

    test "returns error when email is empty string" do
      channel = build_channel(%{"email" => ""})
      monitor = build_monitor()
      incident = build_incident()

      assert {:error, "No email address configured"} =
               EmailAlert.send_incident_alert(channel, incident, monitor)
    end

    test "includes monitor details in email body" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident()

      assert {:ok, _} = EmailAlert.send_incident_alert(channel, incident, monitor)

      assert_email_sent(fn email ->
        assert email.html_body =~ "Test Monitor"
        assert email.html_body =~ "https://example.com"
        assert email.html_body =~ "HTTP 500"
        assert email.text_body =~ "Test Monitor"
        assert email.text_body =~ "https://example.com"
      end)
    end

    test "delays notification when user has hourly frequency" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident()
      user = build_user(%{"notification_frequency" => "hourly"})

      assert {:delayed, "test@example.com"} =
               EmailAlert.send_incident_alert(channel, incident, monitor, user)
    end

    test "sends immediately when user has immediate frequency" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident()
      user = build_user(%{"notification_frequency" => "immediate"})

      assert {:ok, "test@example.com"} =
               EmailAlert.send_incident_alert(channel, incident, monitor, user)
    end

    test "sends immediately when no user provided" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident()

      assert {:ok, "test@example.com"} =
               EmailAlert.send_incident_alert(channel, incident, monitor)
    end
  end

  describe "send_resolution_alert/4" do
    test "sends resolution email with correct subject" do
      channel = build_channel()
      monitor = build_monitor()

      incident =
        build_incident(%{
          status: "resolved",
          resolved_at: ~U[2026-01-15 11:30:00Z],
          duration: 3600
        })

      assert {:ok, "test@example.com"} =
               EmailAlert.send_resolution_alert(channel, incident, monitor)

      assert_email_sent(
        to: [{"", "test@example.com"}],
        subject: "✅ Resolved: Test Monitor is back UP"
      )
    end

    test "includes duration in resolution email" do
      channel = build_channel()
      monitor = build_monitor()

      incident =
        build_incident(%{
          status: "resolved",
          resolved_at: ~U[2026-01-15 11:30:00Z],
          duration: 3600
        })

      assert {:ok, _} = EmailAlert.send_resolution_alert(channel, incident, monitor)

      assert_email_sent(fn email ->
        assert email.html_body =~ "1 hours, 0 minutes"
        assert email.text_body =~ "1 hours, 0 minutes"
      end)
    end

    test "returns error when no email configured" do
      channel = build_channel(%{"email" => nil})
      monitor = build_monitor()
      incident = build_incident()

      assert {:error, "No email address configured"} =
               EmailAlert.send_resolution_alert(channel, incident, monitor)
    end

    test "delays when user has daily frequency" do
      channel = build_channel()
      monitor = build_monitor()
      incident = build_incident(%{resolved_at: ~U[2026-01-15 11:30:00Z], duration: 60})
      user = build_user(%{"notification_frequency" => "daily"})

      assert {:delayed, "test@example.com"} =
               EmailAlert.send_resolution_alert(channel, incident, monitor, user)
    end
  end

  describe "send_test_alert/1" do
    test "sends test email" do
      channel = build_channel()

      assert {:ok, "test@example.com"} = EmailAlert.send_test_alert(channel)

      assert_email_sent(
        to: [{"", "test@example.com"}],
        subject: "Test Alert from Uptrack"
      )
    end

    test "returns error when no email configured" do
      channel = build_channel(%{"email" => nil})

      assert {:error, "No email address configured"} = EmailAlert.send_test_alert(channel)
    end
  end
end
