defmodule Uptrack.Alerting.MattermostAlertTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.MattermostAlert
  alias Uptrack.Monitoring.{AlertChannel, Incident, Monitor}

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

    channel = %AlertChannel{
      id: Ecto.UUID.generate(),
      name: "Mattermost Test",
      type: "mattermost",
      config: %{"webhook_url" => "https://mattermost.example.com/hooks/test123"},
      organization_id: org.id
    }

    incident = %Incident{
      id: Ecto.UUID.generate(),
      monitor_id: monitor.id,
      organization_id: org.id,
      status: "ongoing",
      cause: "HTTP 500",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %{channel: channel, incident: incident, monitor: monitor}
  end

  describe "send_test_alert/1" do
    test "returns error when no webhook URL configured" do
      channel = %AlertChannel{config: %{}}
      assert {:error, "No Mattermost webhook URL configured"} = MattermostAlert.send_test_alert(channel)
    end

    test "returns error when webhook URL is empty" do
      channel = %AlertChannel{config: %{"webhook_url" => ""}}
      assert {:error, "No Mattermost webhook URL configured"} = MattermostAlert.send_test_alert(channel)
    end
  end

  describe "send_incident_alert/3" do
    test "returns error when no webhook URL" do
      channel = %AlertChannel{config: %{}}
      incident = %Incident{started_at: DateTime.utc_now() |> DateTime.truncate(:second), cause: "test"}
      monitor = %Monitor{name: "Test", url: "https://example.com"}

      assert {:error, _} = MattermostAlert.send_incident_alert(channel, incident, monitor)
    end
  end

  describe "send_resolution_alert/3" do
    test "returns error when no webhook URL" do
      channel = %AlertChannel{config: %{}}
      incident = %Incident{resolved_at: DateTime.utc_now() |> DateTime.truncate(:second), duration: 300}
      monitor = %Monitor{name: "Test", url: "https://example.com"}

      assert {:error, _} = MattermostAlert.send_resolution_alert(channel, incident, monitor)
    end
  end
end
