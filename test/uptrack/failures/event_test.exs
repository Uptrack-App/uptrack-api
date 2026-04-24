defmodule Uptrack.Failures.EventTest do
  use ExUnit.Case, async: true

  alias Uptrack.Failures.Event
  alias Uptrack.Monitoring.{Monitor, MonitorCheck}

  @monitor %Monitor{
    id: "019daf00-0000-7000-8000-000000000001",
    organization_id: "019daf00-0000-7000-8000-000000000002",
    url: "https://example.com",
    monitor_type: "http"
  }

  describe "new_from_check/3" do
    test "builds a :check_failed event by default" do
      check = %MonitorCheck{
        status: "down",
        status_code: 503,
        response_time: 187,
        response_body: "boom",
        error_message: "upstream unavailable",
        checked_at: ~U[2026-04-21 12:00:00Z]
      }

      event = Event.new_from_check(check, @monitor)

      assert event.monitor_id == @monitor.id
      assert event.event_type == :check_failed
      assert event.status_code == 503
      assert event.response_time_ms == 187
      assert event.error_message == "upstream unavailable"
      assert event.body == "boom"
      assert event.body_truncated == false
      assert event.body_bytes_total == 4
      assert is_binary(event.body_sha256)
      assert byte_size(event.body_sha256) == 64
      assert event.fingerprint |> elem(0) == 503
    end

    test "accepts :event_type override for state_change events" do
      check = %MonitorCheck{
        status: "up",
        status_code: 200,
        response_time: 42,
        checked_at: ~U[2026-04-21 12:00:00Z]
      }

      event = Event.new_from_check(check, @monitor, event_type: :state_change_up)
      assert event.event_type == :state_change_up
    end

    test "truncates body > 64 KB and sets flags" do
      big_body = :binary.copy("x", 100_000)

      check = %MonitorCheck{
        status: "down",
        status_code: 500,
        response_body: big_body,
        checked_at: ~U[2026-04-21 12:00:00Z]
      }

      event = Event.new_from_check(check, @monitor)

      assert event.body_truncated == true
      assert byte_size(event.body) == Event.body_cap_bytes()
      assert event.body_bytes_total == 100_000
      # sha256 is of the full body, not the truncated copy
      expected = :crypto.hash(:sha256, big_body) |> Base.encode16(case: :lower)
      assert event.body_sha256 == expected
    end

    test "nil body produces nil body + body_sha256 + body_truncated=false" do
      check = %MonitorCheck{
        status: "down",
        status_code: 0,
        response_body: nil,
        checked_at: ~U[2026-04-21 12:00:00Z]
      }

      event = Event.new_from_check(check, @monitor)
      assert event.body == nil
      assert event.body_truncated == false
      assert event.body_sha256 == nil
      assert event.body_bytes_total == 0
    end
  end

  describe "new_lifecycle/3" do
    test "builds an :incident_created event with trace_id and incident_id" do
      event =
        Event.new_lifecycle(:incident_created, @monitor,
          incident_id: "incid-1",
          trace_id: "trace-1",
          error_message: "Monitor down"
        )

      assert event.event_type == :incident_created
      assert event.incident_id == "incid-1"
      assert event.trace_id == "trace-1"
      assert event.error_message == "Monitor down"
      assert event.monitor_url == @monitor.url
    end

    test "rejects non-lifecycle event types via function head guard" do
      assert_raise FunctionClauseError, fn ->
        Event.new_lifecycle(:check_failed, @monitor)
      end
    end
  end
end
