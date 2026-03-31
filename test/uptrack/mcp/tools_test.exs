defmodule Uptrack.MCP.ToolsTest do
  use Uptrack.DataCase

  alias Uptrack.MCP.Tools

  import Uptrack.MonitoringFixtures

  @moduletag :capture_log

  describe "definitions/0" do
    test "returns a list of tool definitions" do
      tools = Tools.definitions()
      assert is_list(tools)
      assert length(tools) >= 10

      for tool <- tools do
        assert is_binary(tool["name"])
        assert is_binary(tool["description"])
        assert is_map(tool["inputSchema"])
      end
    end

    test "all tools have unique names" do
      names = Tools.definitions() |> Enum.map(& &1["name"])
      assert length(names) == length(Enum.uniq(names))
    end
  end

  describe "call/3" do
    setup do
      {user, org} = user_with_org_fixture()
      %{user: user, org: org}
    end

    test "list_monitors returns monitors", %{user: user, org: org} do
      monitor_fixture(user_id: user.id, organization_id: org.id)

      assert {:ok, monitors} = Tools.call("list_monitors", %{}, org.id)
      assert length(monitors) >= 1
      assert hd(monitors).url
      assert hd(monitors).name
    end

    test "list_monitors returns empty for org with no monitors", %{org: org} do
      assert {:ok, []} = Tools.call("list_monitors", %{}, org.id)
    end

    test "get_monitor returns monitor details", %{user: user, org: org} do
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      assert {:ok, details} = Tools.call("get_monitor", %{"monitor_id" => monitor.id}, org.id)
      assert details.id == monitor.id
      assert details.name == monitor.name
    end

    test "get_monitor returns error for wrong org", %{org: org} do
      other_org = organization_fixture()
      {other_user, _} = user_with_org_fixture()
      monitor = monitor_fixture(user_id: other_user.id, organization_id: other_org.id)

      assert {:error, "Monitor not found"} = Tools.call("get_monitor", %{"monitor_id" => monitor.id}, org.id)
    end

    test "list_incidents returns incidents", %{org: org} do
      assert {:ok, incidents} = Tools.call("list_incidents", %{}, org.id)
      assert is_list(incidents)
    end

    test "get_dashboard_stats returns stats", %{org: org} do
      assert {:ok, stats} = Tools.call("get_dashboard_stats", %{}, org.id)
      assert Map.has_key?(stats, :overall_uptime_30d)
    end

    test "list_status_pages returns pages", %{org: org} do
      assert {:ok, pages} = Tools.call("list_status_pages", %{}, org.id)
      assert is_list(pages)
    end

    test "list_alert_channels returns channels", %{org: org} do
      assert {:ok, channels} = Tools.call("list_alert_channels", %{}, org.id)
      assert is_list(channels)
    end

    test "unknown tool returns error", %{org: org} do
      assert {:error, "Unknown tool: fake_tool"} = Tools.call("fake_tool", %{}, org.id)
    end

    test "delete_monitor works", %{user: user, org: org} do
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      assert {:ok, %{deleted: true}} = Tools.call("delete_monitor", %{"monitor_id" => monitor.id}, org.id)
    end

    test "pause_monitor works", %{user: user, org: org} do
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id)

      assert {:ok, result} = Tools.call("pause_monitor", %{"monitor_id" => monitor.id}, org.id)
      assert result.is_active == false
    end

    test "resume_monitor works", %{user: user, org: org} do
      monitor = monitor_fixture(user_id: user.id, organization_id: org.id, status: "paused")

      assert {:ok, result} = Tools.call("resume_monitor", %{"monitor_id" => monitor.id}, org.id)
      assert result.is_active == true
    end
  end
end
