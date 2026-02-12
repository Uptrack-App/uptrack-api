defmodule Uptrack.Monitoring.SchedulerWorkerTest do
  use Uptrack.DataCase, async: true

  import Uptrack.MonitoringFixtures

  alias Uptrack.Monitoring.SchedulerWorker

  @moduletag :capture_log

  describe "perform/1" do
    test "enqueues check jobs for active monitors that need checking" do
      monitor = monitor_fixture(status: "active")

      assert :ok = SchedulerWorker.perform(%Oban.Job{})

      jobs =
        from(j in "oban_jobs",
          where: j.queue == "monitor_checks",
          select: j.args
        )
        |> Uptrack.ObanRepo.all(prefix: "oban")

      monitor_ids = Enum.map(jobs, fn args -> args["monitor_id"] end)
      assert monitor.id in monitor_ids
    end

    test "does not enqueue jobs for paused monitors" do
      paused = monitor_fixture(status: "paused")

      assert :ok = SchedulerWorker.perform(%Oban.Job{})

      jobs =
        from(j in "oban_jobs",
          where: j.queue == "monitor_checks",
          select: j.args
        )
        |> Uptrack.ObanRepo.all(prefix: "oban")

      monitor_ids = Enum.map(jobs, fn args -> args["monitor_id"] end)
      refute paused.id in monitor_ids
    end

    test "does not enqueue jobs for monitors checked recently" do
      monitor = monitor_fixture(status: "active", interval: 300)

      Uptrack.Monitoring.create_monitor_check(%{
        monitor_id: monitor.id,
        status: "up",
        response_time: 100,
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      assert :ok = SchedulerWorker.perform(%Oban.Job{})

      jobs =
        from(j in "oban_jobs",
          where: j.queue == "monitor_checks",
          select: j.args
        )
        |> Uptrack.ObanRepo.all(prefix: "oban")

      monitor_ids = Enum.map(jobs, fn args -> args["monitor_id"] end)
      refute monitor.id in monitor_ids
    end

    test "enqueues jobs for monitors whose interval has elapsed" do
      monitor = monitor_fixture(status: "active", interval: 61)

      Uptrack.Monitoring.create_monitor_check(%{
        monitor_id: monitor.id,
        status: "up",
        response_time: 100,
        checked_at: DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:second)
      })

      assert :ok = SchedulerWorker.perform(%Oban.Job{})

      jobs =
        from(j in "oban_jobs",
          where: j.queue == "monitor_checks",
          select: j.args
        )
        |> Uptrack.ObanRepo.all(prefix: "oban")

      monitor_ids = Enum.map(jobs, fn args -> args["monitor_id"] end)
      assert monitor.id in monitor_ids
    end
  end
end
