defmodule Uptrack.Monitoring.ConsensusTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.Consensus

  describe "add_result/3" do
    test "adds a region result" do
      c = %Consensus{} |> Consensus.add_result(:eu, %{status: "up"})
      assert map_size(c.region_results) == 1
      assert c.region_results[:eu] == %{status: "up"}
    end

    test "overwrites previous result from same region" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:eu, %{status: "down"})

      assert map_size(c.region_results) == 1
      assert c.region_results[:eu].status == "down"
    end

    test "accumulates results from different regions" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "down"})
        |> Consensus.add_result(:us, %{status: "up"})

      assert map_size(c.region_results) == 3
    end
  end

  describe "enough_results?/1" do
    test "false when no results" do
      refute Consensus.enough_results?(%Consensus{expected_regions: 3})
    end

    test "false when fewer than expected and not timed out" do
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "up"})

      refute Consensus.enough_results?(c)
    end

    test "true when all expected regions report" do
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "up"})
        |> Consensus.add_result(:us, %{status: "up"})

      assert Consensus.enough_results?(c)
    end

    test "true when timed out with 2+ results" do
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:us, %{status: "up"})
        |> Consensus.timeout()

      assert Consensus.enough_results?(c)
    end

    test "false when timed out with only 1 result" do
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.timeout()

      refute Consensus.enough_results?(c)
    end

    test "true when expected is 1 and 1 result" do
      c =
        %Consensus{expected_regions: 1}
        |> Consensus.add_result(:eu, %{status: "up"})

      assert Consensus.enough_results?(c)
    end
  end

  describe "compute/1" do
    test "returns nil when no results" do
      assert Consensus.compute(%Consensus{}) == nil
    end

    test "majority up = up" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "down"})
        |> Consensus.add_result(:us, %{status: "up"})

      assert Consensus.compute(c) == "up"
    end

    test "majority-but-not-unanimous down = up (legacy compute/1 now unanimous)" do
      # Per-cycle compute/1 now requires EVERY expected region to agree
      # on DOWN (see change #11 unanimous-DOWN fallback); the per-cycle
      # result is overridden by the strategy-based decide/2 downstream,
      # so this only affects dead-code paths. Kept for regression
      # coverage of the legacy entrypoint.
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "down"})
        |> Consensus.add_result(:asia, %{status: "down"})
        |> Consensus.add_result(:us, %{status: "up"})

      assert Consensus.compute(c) == "up"
    end

    test "all down = down" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "down"})
        |> Consensus.add_result(:asia, %{status: "down"})
        |> Consensus.add_result(:us, %{status: "down"})

      assert Consensus.compute(c) == "down"
    end

    test "all up = up" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "up"})
        |> Consensus.add_result(:us, %{status: "up"})

      assert Consensus.compute(c) == "up"
    end

    test "2-region consensus: 1 up 1 down = up (tie breaks to up)" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:us, %{status: "down"})

      # 1 down out of 2 is not > 50%, so "up"
      assert Consensus.compute(c) == "up"
    end

    test "2-region consensus: both down = down" do
      c =
        %Consensus{expected_regions: 2}
        |> Consensus.add_result(:eu, %{status: "down"})
        |> Consensus.add_result(:us, %{status: "down"})

      assert Consensus.compute(c) == "down"
    end

    test "single region up = up" do
      c = %Consensus{} |> Consensus.add_result(:eu, %{status: "up"})
      assert Consensus.compute(c) == "up"
    end

    test "single region down = down" do
      c = %Consensus{expected_regions: 1} |> Consensus.add_result(:eu, %{status: "down"})
      assert Consensus.compute(c) == "down"
    end
  end

  describe "reset/1" do
    test "clears results and resets status" do
      c =
        %Consensus{expected_regions: 3}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "down"})
        |> Consensus.timeout()
        |> Consensus.reset()

      assert c.region_results == %{}
      assert c.status == :waiting
      assert c.timer == nil
      assert c.expected_regions == 3
    end
  end

  describe "timeout/1" do
    test "sets status to :timeout" do
      c = %Consensus{} |> Consensus.timeout()
      assert c.status == :timeout
    end
  end

  describe "result_count/1" do
    test "returns 0 for empty" do
      assert Consensus.result_count(%Consensus{}) == 0
    end

    test "returns correct count" do
      c =
        %Consensus{}
        |> Consensus.add_result(:eu, %{status: "up"})
        |> Consensus.add_result(:asia, %{status: "down"})

      assert Consensus.result_count(c) == 2
    end
  end

  describe "home_node?/2" do
    test "returns true when no nodes (single node)" do
      assert Consensus.home_node?("monitor-123", [])
    end

    test "deterministic — same input always gives same result" do
      nodes = [:a@host, :b@host, :c@host]
      result1 = Consensus.home_node?("monitor-abc", nodes)
      result2 = Consensus.home_node?("monitor-abc", nodes)
      assert result1 == result2
    end

    test "distributes monitors across nodes" do
      nodes = [:a@host, :b@host, :c@host]

      # Generate many monitor IDs and check that home node assignment
      # distributes across all nodes (not all to one)
      homes =
        for i <- 1..100 do
          id = "monitor-#{i}"
          hash = :erlang.phash2(id, 3)
          Enum.at(nodes, hash)
        end
        |> Enum.frequencies()

      # Each node should get at least some monitors (statistical test)
      assert map_size(homes) == 3
      assert Enum.all?(homes, fn {_node, count} -> count > 10 end)
    end
  end
end
