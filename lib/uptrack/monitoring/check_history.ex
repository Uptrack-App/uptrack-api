defmodule Uptrack.Monitoring.CheckHistory do
  @moduledoc """
  Pure ring-buffer helpers for per-worker sample history.

  Each worker contributes a list of `:up | :down` samples. The list is
  kept newest-first and capped at `@default_size` (21, matching Nagios'
  `max_check_result_history`). Operations are allocation-light because
  the buffer is tiny.
  """

  @default_size 21

  @type sample :: :up | :down
  @type buffer :: [sample()]
  @type history :: %{optional(any()) => buffer()}

  @doc "Returns the canonical history size."
  def default_size, do: @default_size

  @doc """
  Appends a sample to the buffer for `worker`. Older samples beyond
  `size` are dropped. Missing workers are initialized on first push.
  """
  @spec push(history(), any(), sample(), pos_integer()) :: history()
  def push(history, worker, sample, size \\ @default_size)
      when sample in [:up, :down] and is_integer(size) and size > 0 do
    prev = Map.get(history, worker, [])
    Map.put(history, worker, [sample | prev] |> Enum.take(size))
  end

  @doc """
  Returns the last `n` samples for `worker`, newest first. Empty list
  when the worker has no buffer yet.
  """
  @spec last_n(history(), any(), non_neg_integer()) :: [sample()]
  def last_n(history, worker, n) when is_integer(n) and n >= 0 do
    history
    |> Map.get(worker, [])
    |> Enum.take(n)
  end

  @doc "Counts occurrences of `state` in the last `n` samples for `worker`."
  @spec count_state(history(), any(), sample(), non_neg_integer()) :: non_neg_integer()
  def count_state(history, worker, state, n) when state in [:up, :down] do
    history
    |> last_n(worker, n)
    |> Enum.count(&(&1 == state))
  end

  @doc """
  Returns the list of workers tracked in `history`. Useful when the
  consensus strategy needs to iterate every known worker even if only
  some contributed recent samples.
  """
  @spec workers(history()) :: [any()]
  def workers(history), do: Map.keys(history)

  @doc """
  Removes any worker entry whose buffer is empty. Keeps the history map
  lean; safe to call before deciding consensus.
  """
  @spec compact(history()) :: history()
  def compact(history) do
    :maps.filter(fn _w, buf -> buf != [] end, history)
  end
end
