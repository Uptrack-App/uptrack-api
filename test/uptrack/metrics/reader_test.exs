defmodule Uptrack.Metrics.ReaderTest do
  use ExUnit.Case, async: true

  alias Uptrack.Metrics.Reader

  @moduletag :capture_log

  describe "get_uptime_percentage/3" do
    test "returns 100% when VictoriaMetrics is not configured" do
      monitor_id = Uniq.UUID.uuid7()
      start_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      end_time = DateTime.utc_now()

      assert {:ok, 100.0} = Reader.get_uptime_percentage(monitor_id, start_time, end_time)
    end
  end

  describe "get_response_times/3" do
    test "returns empty list when VictoriaMetrics is not configured" do
      monitor_id = Uniq.UUID.uuid7()
      start_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      end_time = DateTime.utc_now()

      assert {:ok, []} = Reader.get_response_times(monitor_id, start_time, end_time)
    end
  end
end
