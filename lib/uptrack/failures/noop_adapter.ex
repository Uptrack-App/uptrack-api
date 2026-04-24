defmodule Uptrack.Failures.NoopAdapter do
  @moduledoc """
  Test-env adapter. Discards events silently. Used to keep tests fast
  and avoid depending on Postgres or VL from unit tests that just
  exercise the `MonitorProcess` dedup logic.
  """

  @behaviour Uptrack.Failures

  @impl true
  def record(_event), do: :ok
end
