defmodule Uptrack.Maintenance.MaintenanceWorkerTest do
  use Uptrack.DataCase

  alias Uptrack.Maintenance
  alias Uptrack.Maintenance.MaintenanceWorker

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  setup do
    {user, org} = user_with_org_fixture()
    %{user: user, org: org}
  end

  defp create_window(org_id, overrides) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      Map.merge(
        %{
          title: "Test Window #{System.unique_integer([:positive])}",
          start_time: DateTime.add(now, 3600, :second),
          end_time: DateTime.add(now, 7200, :second),
          recurrence: "none",
          organization_id: org_id
        },
        overrides
      )

    {:ok, window} = Maintenance.create_maintenance_window(attrs)
    window
  end

  describe "perform/1" do
    test "activates scheduled windows whose start time has passed", %{org: org} do
      past = DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second)
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      # This window should be activated (start time is in the past)
      w1 = create_window(org.id, %{
        start_time: past,
        end_time: future
      })

      # This window should stay scheduled (start time is in the future)
      w2 = create_window(org.id, %{
        start_time: DateTime.add(future, 3600, :second),
        end_time: DateTime.add(future, 7200, :second)
      })

      assert w1.status == "scheduled"
      assert w2.status == "scheduled"

      assert :ok = MaintenanceWorker.perform(%Oban.Job{})

      # Reload windows
      activated = Maintenance.get_maintenance_window(w1.id)
      still_scheduled = Maintenance.get_maintenance_window(w2.id)

      assert activated.status == "active"
      assert still_scheduled.status == "scheduled"
    end

    test "completes active windows whose end time has passed", %{org: org} do
      past_start = DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.truncate(:second)
      past_end = DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second)
      future_end = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      # Create a window that should be completed (both start and end in past)
      w1 = create_window(org.id, %{
        start_time: past_start,
        end_time: past_end
      })

      # Create a window that should stay active (start in past, end in future)
      w2 = create_window(org.id, %{
        start_time: past_start,
        end_time: future_end
      })

      # Single run: activates both (start in past), then completes w1 (end in past)
      assert :ok = MaintenanceWorker.perform(%Oban.Job{})

      completed = Maintenance.get_maintenance_window(w1.id)
      still_active = Maintenance.get_maintenance_window(w2.id)

      # w1: activated then immediately completed (end time already passed)
      assert completed.status == "completed"
      # w2: activated and stays active (end time still in future)
      assert still_active.status == "active"
    end

    test "handles case with no windows to process", %{} do
      assert :ok = MaintenanceWorker.perform(%Oban.Job{})
    end
  end
end
