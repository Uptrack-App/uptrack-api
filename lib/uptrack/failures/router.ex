defmodule Uptrack.Failures.Router do
  @moduledoc """
  Pure routing: maps a `monitor_id` to a shard index using
  `:erlang.phash2/2`. The shard count lives in `:persistent_term`
  (set by `Uptrack.Failures.Batcher` at boot) so lookups are
  lock-free and do not serialize on a GenServer.
  """

  @persistent_term_key {__MODULE__, :shard_count}

  @doc false
  @spec put_shard_count(pos_integer()) :: :ok
  def put_shard_count(n) when is_integer(n) and n > 0 do
    :persistent_term.put(@persistent_term_key, n)
  end

  @doc "Returns the active shard count, or 1 if not yet initialized."
  @spec shard_count() :: pos_integer()
  def shard_count do
    :persistent_term.get(@persistent_term_key, 1)
  end

  @doc "Returns the registered name atom of the shard that owns the given monitor_id."
  @spec shard_name(String.t()) :: atom()
  def shard_name(monitor_id) when is_binary(monitor_id) do
    idx = :erlang.phash2(monitor_id, shard_count())
    :"Elixir.Uptrack.Failures.Batcher.Shard.#{idx}"
  end
end
