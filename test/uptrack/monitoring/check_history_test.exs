defmodule Uptrack.Monitoring.CheckHistoryTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.CheckHistory

  describe "push/4" do
    test "initializes a worker on first push" do
      h = CheckHistory.push(%{}, "eu", :up)
      assert CheckHistory.last_n(h, "eu", 10) == [:up]
    end

    test "keeps newest-first ordering" do
      h =
        %{}
        |> CheckHistory.push("eu", :up)
        |> CheckHistory.push("eu", :down)
        |> CheckHistory.push("eu", :up)

      assert CheckHistory.last_n(h, "eu", 3) == [:up, :down, :up]
    end

    test "caps buffer at size" do
      h =
        Enum.reduce(1..25, %{}, fn i, acc ->
          CheckHistory.push(acc, "eu", if(rem(i, 2) == 0, do: :up, else: :down), 5)
        end)

      assert length(CheckHistory.last_n(h, "eu", 100)) == 5
    end
  end

  describe "last_n/3" do
    test "returns empty list for unknown worker" do
      assert CheckHistory.last_n(%{}, "us", 5) == []
    end
  end

  describe "count_state/4" do
    test "counts only the requested state within the window" do
      h =
        %{}
        |> CheckHistory.push("eu", :down)
        |> CheckHistory.push("eu", :down)
        |> CheckHistory.push("eu", :up)
        |> CheckHistory.push("eu", :down)

      assert CheckHistory.count_state(h, "eu", :down, 4) == 3
      assert CheckHistory.count_state(h, "eu", :up, 4) == 1
    end

    test "window smaller than buffer truncates" do
      h =
        %{}
        |> CheckHistory.push("eu", :down)
        |> CheckHistory.push("eu", :down)
        |> CheckHistory.push("eu", :up)

      # last_n=1 → only :up (newest)
      assert CheckHistory.count_state(h, "eu", :down, 1) == 0
      assert CheckHistory.count_state(h, "eu", :up, 1) == 1
    end
  end

  describe "workers/1 and compact/1" do
    test "workers lists all keys" do
      h =
        %{}
        |> CheckHistory.push("eu", :up)
        |> CheckHistory.push("us", :down)

      assert Enum.sort(CheckHistory.workers(h)) == ["eu", "us"]
    end

    test "compact drops empty buffers" do
      h = %{"eu" => [:up], "stale" => []}
      assert CheckHistory.compact(h) == %{"eu" => [:up]}
    end
  end
end
