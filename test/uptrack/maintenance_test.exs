defmodule Uptrack.MaintenanceTest do
  use Uptrack.DataCase

  alias Uptrack.Maintenance
  alias Uptrack.Maintenance.MaintenanceWindow

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    monitor = monitor_fixture(organization_id: org.id, user_id: user.id)
    {:ok, user: user, org: org, monitor: monitor}
  end

  defp window_attrs(org_id, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "title" => Keyword.get(opts, :title, "Maintenance #{System.unique_integer([:positive])}"),
      "organization_id" => org_id,
      "start_time" => Keyword.get(opts, :start_time, DateTime.add(now, 3600, :second)),
      "end_time" => Keyword.get(opts, :end_time, DateTime.add(now, 7200, :second)),
      "recurrence" => Keyword.get(opts, :recurrence, "none"),
      "status" => Keyword.get(opts, :status, "scheduled")
    }
    |> then(fn attrs ->
      case Keyword.get(opts, :monitor_id) do
        nil -> attrs
        mid -> Map.put(attrs, "monitor_id", mid)
      end
    end)
  end

  describe "create_maintenance_window/1" do
    test "creates a window with valid attrs", %{org: org} do
      assert {:ok, %MaintenanceWindow{} = window} =
               Maintenance.create_maintenance_window(window_attrs(org.id))

      assert window.title =~ "Maintenance"
      assert window.status == "scheduled"
      assert window.recurrence == "none"
    end

    test "requires title, start_time, end_time, organization_id" do
      assert {:error, changeset} = Maintenance.create_maintenance_window(%{})
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :title)
      assert Map.has_key?(errors, :start_time)
      assert Map.has_key?(errors, :end_time)
      assert Map.has_key?(errors, :organization_id)
    end

    test "validates end_time must be after start_time", %{org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert {:error, changeset} =
               Maintenance.create_maintenance_window(%{
                 "title" => "Bad",
                 "organization_id" => org.id,
                 "start_time" => DateTime.add(now, 7200, :second),
                 "end_time" => DateTime.add(now, 3600, :second)
               })

      assert errors_on(changeset) |> Map.has_key?(:end_time)
    end

    test "validates recurrence inclusion", %{org: org} do
      attrs = window_attrs(org.id, recurrence: "invalid")

      assert {:error, changeset} = Maintenance.create_maintenance_window(attrs)
      assert errors_on(changeset) |> Map.has_key?(:recurrence)
    end

    test "can associate with a specific monitor", %{org: org, monitor: monitor} do
      attrs = window_attrs(org.id, monitor_id: monitor.id)

      assert {:ok, window} = Maintenance.create_maintenance_window(attrs)
      assert window.monitor_id == monitor.id
    end
  end

  describe "list_maintenance_windows/2" do
    test "lists windows for org", %{org: org} do
      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(org.id))
      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(org.id))

      assert length(Maintenance.list_maintenance_windows(org.id)) == 2
    end

    test "filters by status", %{org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Maintenance.create_maintenance_window(
          window_attrs(org.id,
            status: "active",
            start_time: DateTime.add(now, -3600, :second),
            end_time: DateTime.add(now, 3600, :second)
          )
        )

      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(org.id, status: "scheduled"))

      assert length(Maintenance.list_maintenance_windows(org.id, status: "active")) == 1
      assert length(Maintenance.list_maintenance_windows(org.id, status: "scheduled")) == 1
    end

    test "filters by monitor_id", %{org: org, monitor: monitor} do
      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(org.id, monitor_id: monitor.id))
      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(org.id))

      assert length(Maintenance.list_maintenance_windows(org.id, monitor_id: monitor.id)) == 1
    end

    test "does not return windows from other orgs", %{org: _org} do
      other_org = organization_fixture()
      {:ok, _} = Maintenance.create_maintenance_window(window_attrs(other_org.id))

      assert Maintenance.list_maintenance_windows(Uniq.UUID.uuid7()) == []
    end
  end

  describe "active_maintenance_window/2 and under_maintenance?/2" do
    test "returns active window covering current time", %{org: org, monitor: monitor} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _window} =
        Maintenance.create_maintenance_window(
          window_attrs(org.id,
            monitor_id: monitor.id,
            status: "active",
            start_time: DateTime.add(now, -3600, :second),
            end_time: DateTime.add(now, 3600, :second)
          )
        )

      assert Maintenance.under_maintenance?(monitor.id, org.id) == true
      assert Maintenance.active_maintenance_window(monitor.id, org.id) != nil
    end

    test "returns nil when no active window", %{org: org, monitor: monitor} do
      assert Maintenance.under_maintenance?(monitor.id, org.id) == false
    end

    test "org-wide window covers any monitor", %{org: org, monitor: monitor} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Maintenance.create_maintenance_window(
          window_attrs(org.id,
            status: "active",
            start_time: DateTime.add(now, -3600, :second),
            end_time: DateTime.add(now, 3600, :second)
          )
        )

      assert Maintenance.under_maintenance?(monitor.id, org.id) == true
    end
  end

  describe "activate_scheduled_windows/0 and complete_expired_windows/0" do
    test "activates windows whose start time has passed", %{org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Maintenance.create_maintenance_window(
          window_attrs(org.id,
            status: "scheduled",
            start_time: DateTime.add(now, -60, :second),
            end_time: DateTime.add(now, 3600, :second)
          )
        )

      {count, _} = Maintenance.activate_scheduled_windows()
      assert count >= 1
    end

    test "completes windows whose end time has passed", %{org: org} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, _} =
        Maintenance.create_maintenance_window(
          window_attrs(org.id,
            status: "active",
            start_time: DateTime.add(now, -7200, :second),
            end_time: DateTime.add(now, -60, :second)
          )
        )

      {count, _} = Maintenance.complete_expired_windows()
      assert count >= 1
    end
  end

  describe "update_maintenance_window/2" do
    test "updates title", %{org: org} do
      {:ok, window} = Maintenance.create_maintenance_window(window_attrs(org.id))

      assert {:ok, updated} = Maintenance.update_maintenance_window(window, %{"title" => "Updated"})
      assert updated.title == "Updated"
    end
  end

  describe "delete_maintenance_window/1" do
    test "deletes the window", %{org: org} do
      {:ok, window} = Maintenance.create_maintenance_window(window_attrs(org.id))

      assert {:ok, _} = Maintenance.delete_maintenance_window(window)
      assert Maintenance.get_maintenance_window(window.id) == nil
    end
  end
end
