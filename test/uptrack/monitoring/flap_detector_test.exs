defmodule Uptrack.Monitoring.FlapDetectorTest do
  use ExUnit.Case, async: true

  alias Uptrack.Monitoring.FlapDetector

  describe "flap_percent/1" do
    test "returns 0.0 for fewer than 2 samples" do
      assert FlapDetector.flap_percent([]) == 0.0
      assert FlapDetector.flap_percent([:up]) == 0.0
    end

    test "returns 0.0 for a steady-state history" do
      stable = List.duplicate(:up, 21)
      assert FlapDetector.flap_percent(stable) == 0.0
    end

    test "returns ~100.0 for fully alternating history" do
      alternating = for i <- 0..20, do: if(rem(i, 2) == 0, do: :up, else: :down)
      percent = FlapDetector.flap_percent(alternating)
      assert percent > 95.0
      assert percent <= 100.0
    end

    test "pair-level flap is non-zero" do
      assert FlapDetector.flap_percent([:down, :up]) > 0.0
    end
  end

  describe "flapping?/3 with hysteresis" do
    test "enters flapping state above high threshold" do
      refute FlapDetector.flapping?(40.0, false)
      assert FlapDetector.flapping?(60.0, false)
    end

    test "stays flapping between thresholds" do
      assert FlapDetector.flapping?(40.0, true)
      assert FlapDetector.flapping?(30.0, true)
    end

    test "exits flapping state below low threshold" do
      refute FlapDetector.flapping?(20.0, true)
    end

    test "custom thresholds honored" do
      assert FlapDetector.flapping?(70.0, false, high_threshold: 60.0, low_threshold: 40.0)
      refute FlapDetector.flapping?(50.0, false, high_threshold: 60.0, low_threshold: 40.0)
    end
  end
end
