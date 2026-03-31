defmodule Uptrack.Alerting.QuotaTrackerTest do
  use Uptrack.DataCase

  alias Uptrack.Alerting.QuotaTracker

  import Uptrack.MonitoringFixtures

  describe "pure functions" do
    test "can_send? returns true when under limit" do
      assert QuotaTracker.can_send?(5, "pro")   # 5 < 30
    end

    test "can_send? returns false when at limit" do
      refute QuotaTracker.can_send?(30, "pro")  # 30 >= 30
    end

    test "can_send? returns false for free plan" do
      refute QuotaTracker.can_send?(0, "free")  # limit is 0
    end

    test "remaining returns correct count" do
      assert QuotaTracker.remaining(10, "pro") == 20  # 30 - 10
      assert QuotaTracker.remaining(0, "team") == 100
      assert QuotaTracker.remaining(200, "business") == 0
    end

    test "current_month returns YYYY-MM format" do
      month = QuotaTracker.current_month()
      assert String.match?(month, ~r/^\d{4}-\d{2}$/)
    end
  end

  describe "check_and_increment/2" do
    test "allows send and increments" do
      org = organization_fixture(plan: "pro")
      assert :ok = QuotaTracker.check_and_increment(org.id, "pro")

      # Check it incremented
      quota = QuotaTracker.get_or_create_quota(org.id)
      assert quota.used_count == 1
    end

    test "rejects when quota exhausted" do
      org = organization_fixture(plan: "pro")

      # Fill up the quota (pro = 30)
      for _ <- 1..30 do
        QuotaTracker.check_and_increment(org.id, "pro")
      end

      assert {:error, :quota_exhausted} = QuotaTracker.check_and_increment(org.id, "pro")
    end

    test "rejects for free plan (0 quota)" do
      org = organization_fixture()
      assert {:error, :quota_exhausted} = QuotaTracker.check_and_increment(org.id, "free")
    end
  end
end
