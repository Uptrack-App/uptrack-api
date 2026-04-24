defmodule Uptrack.Failures.PostgresAdapter do
  @moduledoc """
  Legacy failure-event writer that persists DOWN-check events to
  `app.monitor_check_failures` via the existing `CheckFailures` helper.

  Lifecycle events (incident_created, _resolved, _upgraded) are
  dropped here — they're represented by rows in `app.incidents` already.
  This adapter exists to keep the on-disk Postgres path intact during
  the transition to VictoriaLogs. When the VL adapter is proven in
  production, the Postgres adapter can be retired.
  """

  @behaviour Uptrack.Failures

  alias Uptrack.Failures.Event
  alias Uptrack.Monitoring.{CheckFailures, MonitorCheck}

  require Logger

  @impl true
  def record(%Event{event_type: :check_failed} = event) do
    check = %MonitorCheck{
      monitor_id: event.monitor_id,
      status: "down",
      status_code: event.status_code,
      response_time: event.response_time_ms,
      response_body: event.body,
      response_headers: event.response_headers,
      error_message: event.error_message,
      checked_at: event.occurred_at
    }

    case CheckFailures.record(check) do
      :ok -> :ok
      :error -> {:error, :postgres_write_failed}
      other -> {:error, other}
    end
  rescue
    e ->
      Logger.warning("PostgresAdapter.record/1 rescue: #{Exception.message(e)}")
      {:error, :postgres_exception}
  end

  # Lifecycle events are no-op for this adapter — incidents live in
  # `app.incidents` already; duplicating them here adds no value.
  def record(%Event{} = _lifecycle_event), do: :ok
end
