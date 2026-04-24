defmodule Uptrack.Monitoring.MonitorProcessTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring.{MonitorProcess, MonitorSupervisor, MonitorRegistry}

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  describe "MonitorProcess lifecycle" do
    test "starts and registers a process" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, pid} = MonitorSupervisor.start_monitor(monitor)
      assert Process.alive?(pid)
      assert {:ok, ^pid} = MonitorRegistry.lookup(monitor.id)
    end

    test "stops a process" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, pid} = MonitorSupervisor.start_monitor(monitor)
      assert Process.alive?(pid)

      :ok = MonitorSupervisor.stop_monitor(monitor.id)
      # Process is terminated by supervisor (may briefly exist before cleanup)
      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "does not start duplicate processes" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, pid1} = MonitorSupervisor.start_monitor(monitor)
      {:ok, pid2} = MonitorSupervisor.start_monitor(monitor)
      assert pid1 == pid2
    end

    test "pause and resume" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, _pid} = MonitorSupervisor.start_monitor(monitor)

      # Pause should not crash
      MonitorProcess.pause(monitor.id)
      assert {:ok, _} = MonitorRegistry.lookup(monitor.id)

      # Resume should not crash
      MonitorProcess.resume(monitor.id)
      assert {:ok, _} = MonitorRegistry.lookup(monitor.id)
    end

    test "update_config does not crash" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, _pid} = MonitorSupervisor.start_monitor(monitor)

      updated = %{monitor | interval: 60}
      MonitorProcess.update_config(monitor.id, updated)

      # Process still alive
      assert {:ok, _} = MonitorRegistry.lookup(monitor.id)
    end
  end

  describe "MonitorRegistry" do
    test "all_ids includes started monitors" do
      {user, org} = user_with_org_fixture()
      m1 = monitor_fixture(user_id: user.id, organization_id: org.id)

      MonitorSupervisor.start_monitor(m1)
      assert m1.id in MonitorRegistry.all_ids()
    end
  end

  describe "init/1 hydration" do
    alias Uptrack.Monitoring

    test "hydrates streak and incident_id from an existing ongoing incident" do
      {user, org} = user_with_org_fixture()

      monitor =
        monitor_fixture(
          user_id: user.id,
          organization_id: org.id,
          confirmation_threshold: 4
        )

      {:ok, incident} =
        Monitoring.create_incident(%{
          monitor_id: monitor.id,
          organization_id: monitor.organization_id,
          cause: "pre-existing"
        })

      {:ok, state} = MonitorProcess.init(monitor)

      assert state.alerted_this_streak == true
      assert state.incident_id == incident.id
      assert state.consecutive_failures == 4
    end

    test "starts clean when no ongoing incident exists" do
      {user, org} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      {:ok, state} = MonitorProcess.init(monitor)

      assert state.alerted_this_streak == false
      assert state.incident_id == nil
      assert state.consecutive_failures == 0
    end
  end
end
