defmodule Uptrack.Monitoring.Consensus.Strategy do
  @moduledoc """
  Behaviour for multi-region consensus strategies.

  A strategy decides whether a monitor is `:up`, `:down`, `:degraded`, or
  `:insufficient_data` given a rolling per-worker history map and the
  monitor's sensitivity options. Strategies SHALL be pure — no DB, no
  HTTP, no GenServer reads.

  Shipped implementations:

    * `Uptrack.Monitoring.Consensus.RollingCount` — Netflix Atlas
      `rolling-count`-style. Default in production.
    * `Uptrack.Monitoring.Consensus.Unanimous` — legacy compat, kept for
      instant rollback via `config :uptrack, :consensus_strategy`.
  """

  @type status :: :up | :down | :degraded | :insufficient_data
  @type worker_name :: String.t() | atom()
  @type sample :: :up | :down
  @type history :: %{worker_name() => [sample()]}
  @type details :: %{optional(atom()) => term()}

  @callback decide(monitor_id :: String.t(), history(), keyword()) ::
              {status(), details()}
end
