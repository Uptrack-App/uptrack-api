defmodule Uptrack.Failures.DualAdapter do
  @moduledoc """
  Transition adapter that writes to Postgres synchronously (durable) and
  VictoriaLogs asynchronously via `Task.Supervisor` (shadow).

  Used during the VL rollout: Postgres remains the source of truth
  while we validate that VL is receiving the same events. Flip the
  `:failures_adapter` config to `Uptrack.Failures.VictoriaLogsAdapter`
  once VL is trusted.
  """

  @behaviour Uptrack.Failures

  alias Uptrack.Failures.{Event, PostgresAdapter, VictoriaLogsAdapter}

  @impl true
  def record(%Event{} = event) do
    # VL first (fire-and-forget) so we don't stall on it.
    VictoriaLogsAdapter.record(event)
    # Postgres second (synchronous) — its return value is what the caller sees.
    PostgresAdapter.record(event)
  end
end
