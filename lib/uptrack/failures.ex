defmodule Uptrack.Failures do
  @moduledoc """
  Forensic-event writer contract.

  Every DOWN-check or incident-lifecycle event flows through this module.
  The concrete backend is chosen at runtime via
  `Application.get_env(:uptrack, :failures_adapter)` and MUST implement
  the `Uptrack.Failures` behaviour.

  Ships with three adapters:

    * `Uptrack.Failures.PostgresAdapter` — durable, writes to the
      existing `app.monitor_check_failures` table. Default.
    * `Uptrack.Failures.VictoriaLogsAdapter` — fire-and-forget POST to
      local `vlagent`. Deployed after VL infrastructure is live.
    * `Uptrack.Failures.DualAdapter` — runs both during cutover so we
      can compare without risking forensic loss.
    * `Uptrack.Failures.NoopAdapter` — for tests.

  `record/1` is fire-and-forget from the caller's perspective: it never
  raises and always returns `:ok` or `{:error, reason}`. Adapters that
  do expensive work are expected to offload via `Task.Supervisor`.
  """

  alias Uptrack.Failures.Event

  @callback record(Event.t()) :: :ok | {:error, term()}

  @spec record(Event.t()) :: :ok | {:error, term()}
  def record(%Event{} = event) do
    adapter().record(event)
  rescue
    e ->
      require Logger
      Logger.warning("Uptrack.Failures.record/1 raised: #{Exception.message(e)}")
      {:error, :adapter_crash}
  end

  @doc "Returns the currently configured adapter module."
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:uptrack, :failures_adapter, Uptrack.Failures.PostgresAdapter)
  end
end
