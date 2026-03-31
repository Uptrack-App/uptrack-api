defmodule Uptrack.Monitoring.SchedulerTest do
  use Uptrack.DataCase

  alias Uptrack.Monitoring

  import Uptrack.MonitoringFixtures

  describe "list_active_monitors/1" do
    test "returns only active monitors" do
      {user, org} = user_with_org_fixture()
      _active = monitor_fixture(user_id: user.id, organization_id: org.id, status: "active")
      _paused = monitor_fixture(user_id: user.id, organization_id: org.id, status: "paused")

      active_monitors = Monitoring.list_active_monitors(org.id)
      assert length(active_monitors) == 1
      assert hd(active_monitors).status == "active"
    end

    test "returns empty for org with no active monitors" do
      org = organization_fixture()
      assert Monitoring.list_active_monitors(org.id) == []
    end
  end
end
