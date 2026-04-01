defmodule Uptrack.OAuth.ScopesTest do
  use ExUnit.Case, async: true

  alias Uptrack.OAuth.Scopes

  describe "all_scopes/0" do
    test "returns all defined scopes" do
      scopes = Scopes.all_scopes()
      assert "monitors:read" in scopes
      assert "monitors:write" in scopes
      assert "incidents:read" in scopes
      assert "analytics:read" in scopes
    end
  end

  describe "required_scope/1" do
    test "read tools require read scope" do
      assert Scopes.required_scope("list_monitors") == "monitors:read"
      assert Scopes.required_scope("get_monitor") == "monitors:read"
      assert Scopes.required_scope("list_incidents") == "incidents:read"
      assert Scopes.required_scope("list_status_pages") == "status_pages:read"
      assert Scopes.required_scope("list_alert_channels") == "alerts:read"
      assert Scopes.required_scope("get_dashboard_stats") == "analytics:read"
    end

    test "write tools require write scope" do
      assert Scopes.required_scope("create_monitor") == "monitors:write"
      assert Scopes.required_scope("delete_monitor") == "monitors:write"
      assert Scopes.required_scope("pause_monitor") == "monitors:write"
      assert Scopes.required_scope("resume_monitor") == "monitors:write"
    end

    test "unknown tool returns nil" do
      assert Scopes.required_scope("unknown_tool") == nil
    end
  end

  describe "authorized?/2" do
    test "read scope authorizes read tool" do
      assert Scopes.authorized?(["monitors:read"], "list_monitors")
    end

    test "read scope does not authorize write tool" do
      refute Scopes.authorized?(["monitors:read"], "create_monitor")
    end

    test "write scope authorizes write tool" do
      assert Scopes.authorized?(["monitors:write"], "create_monitor")
    end

    test "unknown tool is authorized (no scope required)" do
      assert Scopes.authorized?([], "unknown_tool")
    end
  end
end
