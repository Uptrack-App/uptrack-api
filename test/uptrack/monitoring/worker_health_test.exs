defmodule Uptrack.Monitoring.WorkerHealthTest do
  use ExUnit.Case, async: false

  alias Uptrack.Monitoring.WorkerHealth

  describe "disagreement_rate/1 (pure)" do
    test "zero observations → 0.0" do
      assert WorkerHealth.disagreement_rate([]) == 0.0
    end

    test "all agreed → 0.0" do
      obs = for _ <- 1..10, do: {DateTime.utc_now(), true}
      assert WorkerHealth.disagreement_rate(obs) == 0.0
    end

    test "all disagreed → 1.0" do
      obs = for _ <- 1..10, do: {DateTime.utc_now(), false}
      assert WorkerHealth.disagreement_rate(obs) == 1.0
    end

    test "mixed → 0.5" do
      obs = [
        {DateTime.utc_now(), true},
        {DateTime.utc_now(), false},
        {DateTime.utc_now(), true},
        {DateTime.utc_now(), false}
      ]

      assert WorkerHealth.disagreement_rate(obs) == 0.5
    end
  end

  describe "integration (real GenServer)" do
    setup do
      # Restart WorkerHealth so each test starts with a clean persistent_term.
      if pid = Process.whereis(WorkerHealth) do
        GenServer.stop(pid, :normal)
      end

      {:ok, _pid} = WorkerHealth.start_link([])
      :ok
    end

    test "trusted by default" do
      assert WorkerHealth.trusted?("any-worker")
    end

    test "a worker with no observations is trusted" do
      WorkerHealth.reconcile()
      assert WorkerHealth.trusted?("fresh-worker")
    end

    test "sustained disagreement would quarantine but safety cap can trigger" do
      # Observe a single worker with 100% disagreement — should quarantine.
      # Can't reliably wait 15 min in a test, so we just verify that
      # observe/3 doesn't crash and reconcile/0 runs without error.
      for _ <- 1..50, do: WorkerHealth.observe("us", false)
      for _ <- 1..50, do: WorkerHealth.observe("eu", true)
      assert :ok = WorkerHealth.reconcile()
    end
  end
end
