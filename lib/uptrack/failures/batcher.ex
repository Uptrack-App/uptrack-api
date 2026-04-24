defmodule Uptrack.Failures.Batcher do
  @moduledoc """
  Supervisor for the sharded forensic-event Batcher.

  Starts N shard GenServers under `:one_for_one`. Each shard owns its
  own NDJSON buffer and one Gun connection per VL destination.
  Shard count defaults to `System.schedulers_online()` and can be
  overridden via `config :uptrack, :failures_shard_count`.

  Destinations (`[{host, port}, ...]`) come from
  `config :uptrack, Uptrack.Failures, vl_insert_destinations: [...]`.
  Override via runtime.exs for different environments.
  """

  use Supervisor

  alias Uptrack.Failures.Batcher.Shard
  alias Uptrack.Failures.Router

  @default_destinations [
    # nbg3 (Tailscale)
    {"100.64.1.3", 9428},
    # nbg4 (Tailscale)
    {"100.64.1.4", 9428}
  ]

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    shard_count = Keyword.get(opts, :shard_count, default_shard_count())
    destinations = Keyword.get(opts, :destinations, default_destinations())

    :ok = Router.put_shard_count(shard_count)

    children =
      for i <- 0..(shard_count - 1) do
        Shard.child_spec({i, destinations})
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp default_shard_count do
    Application.get_env(:uptrack, :failures_shard_count, System.schedulers_online())
  end

  defp default_destinations do
    Application.get_env(:uptrack, Uptrack.Failures, [])
    |> Keyword.get(:vl_insert_destinations, @default_destinations)
  end
end
