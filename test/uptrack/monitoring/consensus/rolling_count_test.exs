defmodule Uptrack.Monitoring.Consensus.RollingCountTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.CheckHistory
  alias Uptrack.Monitoring.Consensus.RollingCount

  @mid "monitor-1"

  defp down_samples(n), do: List.duplicate(:down, n)
  defp up_samples(n), do: List.duplicate(:up, n)

  describe "decide/3 — single-worker graceful degrade" do
    test "1 worker with majority regions_required still fires DOWN when threshold crossed" do
      h = %{"eu" => down_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu"]
        )

      assert status == :down
    end

    test "1 worker UP with majority rule → :up" do
      h = %{"eu" => up_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu"]
        )

      assert status == :up
    end

    test "0 trusted workers → :insufficient_data" do
      {status, details} =
        RollingCount.decide(@mid, %{},
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: []
        )

      assert status == :insufficient_data
      assert details.reason == :no_trusted_workers
    end

    test "with regions_required=any, 1 worker at threshold → :down" do
      h = %{"eu" => down_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "any",
          trusted_workers: ["eu"]
        )

      assert status == :down
    end
  end

  describe "decide/3 — three workers, majority rule" do
    test "all workers down above threshold → :down" do
      h = %{"eu" => down_samples(6), "us" => down_samples(6), "asia" => down_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :down
    end

    test "single flaky worker cannot drive DOWN (3 of 6 samples, below threshold)" do
      h = %{
        "eu" => up_samples(6),
        "us" => [:down, :up, :down, :up, :down, :up],
        "asia" => up_samples(6)
      }

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :up
    end

    test "one worker strongly down → :degraded (not :down, not :up)" do
      h = %{"eu" => down_samples(6), "us" => up_samples(6), "asia" => up_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :degraded
    end

    test "two of three workers down → :down" do
      h = %{"eu" => down_samples(6), "us" => down_samples(6), "asia" => up_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :down
    end
  end

  describe "decide/3 — regions_required=all" do
    test "requires every worker to be down" do
      h = %{"eu" => down_samples(6), "us" => down_samples(6), "asia" => up_samples(6)}

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "all",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :degraded
    end
  end

  describe "decide/3 — flap scenario that previously caused spam" do
    test "worker oscillating up/down/up/down/up/down produces count=3, below threshold" do
      alternating = for i <- 0..5, do: if(rem(i, 2) == 0, do: :down, else: :up)

      h = %{
        "eu" => up_samples(6),
        "us" => alternating,
        "asia" => up_samples(6)
      }

      {status, _} =
        RollingCount.decide(@mid, h,
          confirmation_window: "3m",
          regions_required: "majority",
          trusted_workers: ["eu", "us", "asia"]
        )

      assert status == :up
    end
  end
end
