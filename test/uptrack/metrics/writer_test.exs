defmodule Uptrack.Metrics.WriterTest do
  use ExUnit.Case, async: true

  alias Uptrack.Metrics.Writer

  @moduletag :capture_log

  defp build_monitor do
    %{
      id: Uniq.UUID.uuid7(),
      organization_id: Uniq.UUID.uuid7(),
      name: "Test Monitor"
    }
  end

  defp build_check(attrs \\ %{}) do
    Map.merge(
      %{
        status: "up",
        response_time: 150,
        status_code: 200
      },
      attrs
    )
  end

  describe "write_check_result/2" do
    test "returns :ok when VictoriaMetrics is not configured" do
      # Default config has nil URLs, so writes are silently skipped
      assert :ok = Writer.write_check_result(build_monitor(), build_check())
    end

    test "returns :ok for down check when not configured" do
      check = build_check(%{status: "down", status_code: 500, response_time: 0})
      assert :ok = Writer.write_check_result(build_monitor(), check)
    end
  end

  describe "write_incident_event/2" do
    test "returns :ok when VictoriaMetrics is not configured" do
      assert :ok = Writer.write_incident_event(build_monitor(), "incident_created")
    end
  end
end
