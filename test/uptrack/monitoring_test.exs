defmodule Uptrack.MonitoringTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring

  describe "monitors" do
    alias Uptrack.Monitoring.Monitor

    import Uptrack.MonitoringFixtures

    @invalid_attrs %{
      timeout: nil,
      name: nil,
      status: nil,
      description: nil,
      url: nil,
      monitor_type: nil,
      interval: nil,
      alert_contacts: nil,
      settings: nil
    }

    test "list_monitors/0 returns all monitors" do
      monitor = monitor_fixture()
      assert Monitoring.list_monitors() == [monitor]
    end

    test "get_monitor!/1 returns the monitor with given id" do
      monitor = monitor_fixture()
      assert Monitoring.get_monitor!(monitor.id) == monitor
    end

    test "create_monitor/1 with valid data creates a monitor" do
      valid_attrs = %{
        timeout: 42,
        name: "some name",
        status: "some status",
        description: "some description",
        url: "some url",
        monitor_type: "some monitor_type",
        interval: 42,
        alert_contacts: %{},
        settings: %{}
      }

      assert {:ok, %Monitor{} = monitor} = Monitoring.create_monitor(valid_attrs)
      assert monitor.timeout == 42
      assert monitor.name == "some name"
      assert monitor.status == "some status"
      assert monitor.description == "some description"
      assert monitor.url == "some url"
      assert monitor.monitor_type == "some monitor_type"
      assert monitor.interval == 42
      assert monitor.alert_contacts == %{}
      assert monitor.settings == %{}
    end

    test "create_monitor/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Monitoring.create_monitor(@invalid_attrs)
    end

    test "update_monitor/2 with valid data updates the monitor" do
      monitor = monitor_fixture()

      update_attrs = %{
        timeout: 43,
        name: "some updated name",
        status: "some updated status",
        description: "some updated description",
        url: "some updated url",
        monitor_type: "some updated monitor_type",
        interval: 43,
        alert_contacts: %{},
        settings: %{}
      }

      assert {:ok, %Monitor{} = monitor} = Monitoring.update_monitor(monitor, update_attrs)
      assert monitor.timeout == 43
      assert monitor.name == "some updated name"
      assert monitor.status == "some updated status"
      assert monitor.description == "some updated description"
      assert monitor.url == "some updated url"
      assert monitor.monitor_type == "some updated monitor_type"
      assert monitor.interval == 43
      assert monitor.alert_contacts == %{}
      assert monitor.settings == %{}
    end

    test "update_monitor/2 with invalid data returns error changeset" do
      monitor = monitor_fixture()
      assert {:error, %Ecto.Changeset{}} = Monitoring.update_monitor(monitor, @invalid_attrs)
      assert monitor == Monitoring.get_monitor!(monitor.id)
    end

    test "delete_monitor/1 deletes the monitor" do
      monitor = monitor_fixture()
      assert {:ok, %Monitor{}} = Monitoring.delete_monitor(monitor)
      assert_raise Ecto.NoResultsError, fn -> Monitoring.get_monitor!(monitor.id) end
    end

    test "change_monitor/1 returns a monitor changeset" do
      monitor = monitor_fixture()
      assert %Ecto.Changeset{} = Monitoring.change_monitor(monitor)
    end
  end
end
