defmodule Uptrack.Metrics.RetentionTest do
  use ExUnit.Case, async: true

  alias Uptrack.Metrics.Retention

  describe "days_for_plan/1" do
    test "returns 180 days for free plan" do
      assert Retention.days_for_plan("free") == 180
    end

    test "returns 730 days for pro plan" do
      assert Retention.days_for_plan("pro") == 730
    end

    test "returns 730 days for team plan" do
      assert Retention.days_for_plan("team") == 730
    end

    test "returns 1825 days for business plan" do
      assert Retention.days_for_plan("business") == 1825
    end

    test "returns 180 days for unknown plan" do
      assert Retention.days_for_plan("unknown") == 180
    end
  end

  describe "clamp_range/3" do
    test "clamps start time to plan retention limit" do
      now = DateTime.utc_now()
      one_year_ago = DateTime.add(now, -365 * 86400, :second)

      {clamped_start, end_time} = Retention.clamp_range(one_year_ago, now, "free")

      # Free plan = 180 days, so start should be clamped
      max_start = DateTime.add(now, -180 * 86400, :second)
      assert DateTime.diff(clamped_start, max_start, :second) |> abs() <= 1
      assert end_time == now
    end

    test "does not clamp when within retention limit" do
      now = DateTime.utc_now()
      one_month_ago = DateTime.add(now, -30 * 86400, :second)

      {clamped_start, end_time} = Retention.clamp_range(one_month_ago, now, "free")

      assert DateTime.diff(clamped_start, one_month_ago, :second) |> abs() <= 1
      assert end_time == now
    end

    test "business plan allows 5 years of history" do
      now = DateTime.utc_now()
      three_years_ago = DateTime.add(now, -3 * 365 * 86400, :second)

      {clamped_start, _end_time} = Retention.clamp_range(three_years_ago, now, "business")

      # 3 years is within 5-year limit, so no clamping
      assert DateTime.diff(clamped_start, three_years_ago, :second) |> abs() <= 1
    end
  end

  describe "step_for_days/1" do
    test "returns 5m for 1 day" do
      assert Retention.step_for_days(1) == "5m"
    end

    test "returns 1h for 7 days" do
      assert Retention.step_for_days(7) == "1h"
    end

    test "returns 1d for 30 days" do
      assert Retention.step_for_days(30) == "1d"
    end

    test "returns 1d for 365 days" do
      assert Retention.step_for_days(365) == "1d"
    end
  end
end
