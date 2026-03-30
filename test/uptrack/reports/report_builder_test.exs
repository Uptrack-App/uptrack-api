defmodule Uptrack.Reports.ReportBuilderTest do
  use ExUnit.Case, async: true

  alias Uptrack.Reports.ReportBuilder

  describe "build_summary/1" do
    test "builds summary with monitors and uptime data" do
      monitors = [
        %{id: "m1", name: "API", url: "https://api.example.com", is_active: true},
        %{id: "m2", name: "Web", url: "https://example.com", is_active: true},
        %{id: "m3", name: "Paused", url: "https://old.example.com", is_active: false}
      ]

      uptime_data = [
        %{monitor_id: "m1", uptime: 99.9},
        %{monitor_id: "m1", uptime: 100.0},
        %{monitor_id: "m2", uptime: 98.5},
        %{monitor_id: "m2", uptime: 99.0}
      ]

      report = ReportBuilder.build_summary(%{
        monitors: monitors,
        uptime_data: uptime_data,
        incident_count: 3,
        period: "Mar 23 – Mar 30, 2026"
      })

      assert report.total_monitors == 3
      assert report.active_monitors == 2
      assert report.incident_count == 3
      assert report.period == "Mar 23 – Mar 30, 2026"
      assert is_float(report.overall_uptime)
      assert length(report.monitor_breakdown) == 3
    end

    test "handles empty uptime data" do
      monitors = [%{id: "m1", name: "API", url: "https://api.example.com", is_active: true}]

      report = ReportBuilder.build_summary(%{
        monitors: monitors,
        uptime_data: [],
        incident_count: 0,
        period: "test"
      })

      assert report.overall_uptime == 100.0
    end

    test "handles no monitors" do
      report = ReportBuilder.build_summary(%{
        monitors: [],
        uptime_data: [],
        incident_count: 0,
        period: "test"
      })

      assert report.total_monitors == 0
      assert report.active_monitors == 0
      assert report.monitor_breakdown == []
    end
  end
end
