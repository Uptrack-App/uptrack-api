defmodule Uptrack.Alerting.AlertDeliveryWorkerTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting
  alias Uptrack.Alerting.AlertDeliveryWorker
  import Uptrack.MonitoringFixtures

  describe "backoff/1" do
    test "uses exponential backoff" do
      assert AlertDeliveryWorker.backoff(%Oban.Job{attempt: 1}) == 60
      assert AlertDeliveryWorker.backoff(%Oban.Job{attempt: 2}) == 240
      assert AlertDeliveryWorker.backoff(%Oban.Job{attempt: 3}) == 960
    end
  end

  describe "send_incident_alerts/2" do
    test "enqueues alert delivery jobs for each active channel" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      _channel =
        alert_channel_fixture(
          user_id: user.id,
          organization_id: org.id,
          type: "email",
          config: %{"email" => "test@example.com"}
        )

      {:ok, incident} =
        Uptrack.Monitoring.create_incident(%{
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "ongoing",
          organization_id: org.id,
          monitor_id: monitor.id
        })

      results = Alerting.send_incident_alerts(incident, monitor)

      assert Enum.any?(results, &match?({:ok, :enqueued}, &1))
    end
  end

  describe "send_resolution_alerts/2" do
    test "enqueues resolution alert delivery jobs" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      _channel =
        alert_channel_fixture(
          user_id: user.id,
          organization_id: org.id,
          type: "slack",
          config: %{"webhook_url" => "https://hooks.slack.com/test"}
        )

      started_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-3600, :second)
      resolved_at = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, incident} =
        Uptrack.Monitoring.create_incident(%{
          started_at: started_at,
          resolved_at: resolved_at,
          status: "resolved",
          duration: 3600,
          organization_id: org.id,
          monitor_id: monitor.id
        })

      results = Alerting.send_resolution_alerts(incident, monitor)

      assert Enum.any?(results, &match?({:ok, :enqueued}, &1))
    end
  end
end
