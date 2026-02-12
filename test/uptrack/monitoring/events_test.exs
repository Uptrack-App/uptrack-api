defmodule Uptrack.Monitoring.EventsTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.Events

  @moduletag :capture_log

  defp build_monitor(attrs \\ %{}) do
    Map.merge(
      %Uptrack.Monitoring.Monitor{
        id: Uniq.UUID.uuid7(),
        name: "Test Monitor",
        url: "https://example.com",
        user_id: Uniq.UUID.uuid7(),
        organization_id: Uniq.UUID.uuid7(),
        status: "active",
        monitor_type: "http",
        interval: 300,
        timeout: 30,
        settings: %{},
        alert_contacts: []
      },
      attrs
    )
  end

  defp build_check(monitor, attrs \\ %{}) do
    Map.merge(
      %Uptrack.Monitoring.MonitorCheck{
        id: System.unique_integer([:positive]),
        monitor_id: monitor.id,
        status: "up",
        response_time: 150,
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        error_message: nil
      },
      attrs
    )
  end

  defp build_incident(monitor, attrs \\ %{}) do
    Map.merge(
      %Uptrack.Monitoring.Incident{
        id: Uniq.UUID.uuid7(),
        monitor_id: monitor.id,
        status: "ongoing",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        cause: "Connection timeout"
      },
      attrs
    )
  end

  describe "broadcast_check_completed/2" do
    test "broadcasts to user and monitor channels" do
      monitor = build_monitor()
      check = build_check(monitor)

      Phoenix.PubSub.subscribe(Uptrack.PubSub, "user:#{monitor.user_id}")
      Phoenix.PubSub.subscribe(Uptrack.PubSub, "monitor:#{monitor.id}")

      Events.broadcast_check_completed(check, monitor)

      assert_receive {:check_completed, data}
      assert data.monitor_id == monitor.id
      assert data.status == "up"
      assert data.response_time == 150

      # Also received on monitor channel
      assert_receive {:check_completed, _}
    end
  end

  describe "broadcast_incident_created/2" do
    test "broadcasts incident creation event" do
      monitor = build_monitor()
      incident = build_incident(monitor)

      Phoenix.PubSub.subscribe(Uptrack.PubSub, "user:#{monitor.user_id}")

      Events.broadcast_incident_created(incident, monitor)

      assert_receive {:incident_created, data}
      assert data.incident_id == incident.id
      assert data.monitor_name == "Test Monitor"
      assert data.cause == "Connection timeout"
    end
  end

  describe "broadcast_incident_resolved/2" do
    test "broadcasts incident resolution event" do
      monitor = build_monitor()

      incident =
        build_incident(monitor, %{
          status: "resolved",
          resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
          duration: 120
        })

      Phoenix.PubSub.subscribe(Uptrack.PubSub, "monitor:#{monitor.id}")

      Events.broadcast_incident_resolved(incident, monitor)

      assert_receive {:incident_resolved, data}
      assert data.incident_id == incident.id
      assert data.duration == 120
    end
  end

  describe "broadcast_monitor_status_changed/3" do
    test "broadcasts status change event" do
      monitor = build_monitor()

      Phoenix.PubSub.subscribe(Uptrack.PubSub, "user:#{monitor.user_id}")

      Events.broadcast_monitor_status_changed(monitor, "active", "paused")

      assert_receive {:monitor_status_changed, data}
      assert data.old_status == "active"
      assert data.new_status == "paused"
    end
  end

  describe "broadcast_dashboard_update/2" do
    test "broadcasts dashboard stats" do
      user_id = Uniq.UUID.uuid7()
      stats = %{total_monitors: 5, active_monitors: 4}

      Phoenix.PubSub.subscribe(Uptrack.PubSub, "user:#{user_id}")

      Events.broadcast_dashboard_update(user_id, stats)

      assert_receive {:dashboard_update, data}
      assert data.stats.total_monitors == 5
    end
  end
end
