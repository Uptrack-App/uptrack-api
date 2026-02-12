defmodule Uptrack.AlertingTest do
  use Uptrack.DataCase

  import Uptrack.MonitoringFixtures

  alias Uptrack.Alerting
  alias Uptrack.Monitoring

  @moduletag :capture_log

  describe "alert channels CRUD" do
    test "list_active_alert_channels/1 returns only active channels" do
      {user, org} = user_with_org_fixture()
      active = alert_channel_fixture(organization_id: org.id, user_id: user.id, is_active: true)

      _inactive =
        alert_channel_fixture(
          organization_id: org.id,
          user_id: user.id,
          is_active: false,
          name: "Inactive Channel"
        )

      result = Alerting.list_active_alert_channels(org.id)
      assert length(result) == 1
      assert hd(result).id == active.id
    end

    test "create_alert_channel/1 creates a channel" do
      {user, org} = user_with_org_fixture()

      attrs = %{
        name: "Production Slack",
        type: "slack",
        config: %{"webhook_url" => "https://hooks.slack.com/test"},
        is_active: true,
        organization_id: org.id,
        user_id: user.id
      }

      assert {:ok, channel} = Alerting.create_alert_channel(attrs)
      assert channel.name == "Production Slack"
      assert channel.type == "slack"
    end

    test "update_alert_channel/2 updates channel" do
      channel = alert_channel_fixture()
      assert {:ok, updated} = Alerting.update_alert_channel(channel, %{name: "Updated"})
      assert updated.name == "Updated"
    end

    test "delete_alert_channel/1 removes channel" do
      channel = alert_channel_fixture()
      assert {:ok, _} = Alerting.delete_alert_channel(channel)
      assert_raise Ecto.NoResultsError, fn -> Alerting.get_alert_channel!(channel.id) end
    end
  end

  describe "send_incident_alerts/2" do
    test "enqueues alert delivery jobs for active channels" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)
      _channel = alert_channel_fixture(organization_id: org.id, user_id: user.id, is_active: true)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Connection timeout"
        })

      results = Alerting.send_incident_alerts(incident, monitor)
      assert Enum.any?(results, fn r -> match?({:ok, _}, r) end)
    end

    test "skips when user has disabled notifications" do
      {user, org} = user_with_org_fixture()

      # Disable email notifications entirely
      {:ok, _} =
        Uptrack.Accounts.update_user(user, %{
          notification_preferences: %{"email_enabled" => false}
        })

      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)
      _channel = alert_channel_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Error"
        })

      results = Alerting.send_incident_alerts(incident, monitor)
      assert [{:skipped_user_preferences, _}] = results
    end

    test "returns empty results when no active channels exist" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Down"
        })

      results = Alerting.send_incident_alerts(incident, monitor)
      assert results == []
    end
  end

  describe "send_resolution_alerts/2" do
    test "enqueues resolution jobs for active channels" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(organization_id: org.id, user_id: user.id)
      _channel = alert_channel_fixture(organization_id: org.id, user_id: user.id, is_active: true)

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: org.id,
          cause: "Error"
        })

      {:ok, resolved} = Monitoring.resolve_incident(incident)

      results = Alerting.send_resolution_alerts(resolved, monitor)
      assert Enum.any?(results, fn r -> match?({:ok, _}, r) end)
    end
  end

  describe "send_test_alert/1" do
    test "dispatches to the correct channel handler" do
      channel = alert_channel_fixture(type: "email", config: %{"email" => "test@example.com"})

      # Email test alerts go through Swoosh test adapter
      result = Alerting.send_test_alert(channel)
      assert match?({:ok, _}, result)
    end

    test "returns error for unknown channel type" do
      channel = alert_channel_fixture()
      # Manually update type to something unknown
      channel = %{channel | type: "carrier_pigeon"}

      assert {:error, "Unknown alert channel type: carrier_pigeon"} =
               Alerting.send_test_alert(channel)
    end
  end
end
