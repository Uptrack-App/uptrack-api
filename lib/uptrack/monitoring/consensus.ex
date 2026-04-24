defmodule Uptrack.Monitoring.Consensus do
  @moduledoc """
  Pure consensus logic for multi-region check results.

  Two layers live in this module:

    1. **Per-cycle accumulator** (`%Consensus{}` struct). `add_result`,
       `enough_results?`, `compute`, `reset`, `timeout` — same API as
       before change #11. Used by `MonitorProcess` to gather region
       results within a single check window before handing off to the
       strategy-based decider.

    2. **Strategy-based decider** (`decide/2`). Dispatches to the
       configured `Consensus.Strategy` implementation — rolling-count
       by default, unanimous for rollback. Operates on a rolling
       per-worker history rather than a single cycle snapshot.

  Both are pure. No DB, no HTTP, no GenServer reads.

  The active strategy is resolved via `:persistent_term` (set once at
  app boot in `Uptrack.Application.start/2`), so dispatch is lock-free
  on the hot path.
  """

  alias Uptrack.Monitoring.Consensus.RollingCount

  @persistent_term_key __MODULE__

  defstruct region_results: %{},
            expected_regions: 3,
            timer: nil,
            status: :waiting

  @type t :: %__MODULE__{
          region_results: %{String.t() => map()},
          expected_regions: pos_integer(),
          timer: reference() | nil,
          status: :waiting | :ready | :timeout
        }

  # --- Pure functions ---

  @doc "Adds a region's check result."
  @spec add_result(t(), String.t(), map()) :: t()
  def add_result(%__MODULE__{} = c, region, result) do
    %{c | region_results: Map.put(c.region_results, region, result)}
  end

  @doc """
  Do we have enough results to compute consensus?

  - All expected regions reported → true
  - Timeout with a strict majority of expected regions reporting → true
    (strict majority means `received * 2 > expected`, so minority-region
    failures can't fire a verdict if the rest of the mesh hasn't weighed in)
  - Otherwise → false (still waiting / insufficient data)
  """
  @spec enough_results?(t()) :: boolean()
  def enough_results?(%__MODULE__{} = c) do
    received = map_size(c.region_results)

    cond do
      received >= c.expected_regions -> true
      c.status == :timeout and received * 2 > c.expected_regions -> true
      true -> false
    end
  end

  @doc """
  Computes consensus: **unanimous** down = down, otherwise up.

  Rationale: a single flaky region (e.g. a worker with a misconfigured
  TLS stack) would otherwise drag consensus to DOWN via majority vote
  the moment a second region times out, causing alert flapping. By
  requiring every reporting region to agree on DOWN, a real outage
  still fires (all regions lose the target together) while transient
  per-region issues stay silent. A single-region monitor still works
  — `total == 1` means unanimous == that-one-region.

  Trade-off: a genuine one-region-only outage (e.g. a monitor that is
  geographically gated) will not fire. At current scale this is an
  acceptable loss of sensitivity vs. the cost of alert spam.

  Returns nil if no results, "down" or "up" otherwise.
  """
  @spec compute(t()) :: String.t() | nil
  def compute(%__MODULE__{region_results: results}) when map_size(results) == 0 do
    nil
  end

  def compute(%__MODULE__{region_results: results, expected_regions: expected}) do
    received = map_size(results)
    down_count = Enum.count(results, fn {_region, r} -> r.status == "down" end)

    # DOWN only when EVERY expected region has reported and all agree.
    # A missing region (timeout) is treated as implicitly UP — refusing
    # to let silence plus a couple of flaky workers produce a false
    # DOWN verdict.
    cond do
      received >= expected and down_count == expected -> "down"
      true -> "up"
    end
  end

  @doc "Resets for next check cycle."
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = c) do
    %{c | region_results: %{}, status: :waiting, timer: nil}
  end

  @doc "Marks as timed out (evaluate with partial results)."
  @spec timeout(t()) :: t()
  def timeout(%__MODULE__{} = c) do
    %{c | status: :timeout}
  end

  @doc "Returns the number of results received so far."
  @spec result_count(t()) :: non_neg_integer()
  def result_count(%__MODULE__{region_results: r}), do: map_size(r)

  @doc """
  Checks if the current node is the home node for a monitor.

  Deterministic hash-based assignment for alert deduplication.
  Pure — accepts sorted_nodes as parameter, does not call Node.list().
  """
  @spec home_node?(String.t(), [node()]) :: boolean()
  def home_node?(monitor_id, sorted_nodes) do
    node_count = length(sorted_nodes)

    if node_count == 0 do
      true
    else
      hash = :erlang.phash2(monitor_id, node_count)
      Enum.at(sorted_nodes, hash) == node()
    end
  end

  # --- Strategy dispatch (change #11) ---

  @doc """
  Returns the active consensus strategy module. Resolved from
  `:persistent_term`, falling back to `RollingCount` when unset. Runs
  in < 1 µs on the hot path.
  """
  @spec strategy() :: module()
  def strategy do
    :persistent_term.get(@persistent_term_key, RollingCount)
  end

  @doc """
  Sets the active strategy at app boot. Callers SHOULD NOT invoke this
  at runtime — use a rolling restart to change strategies. Kept public
  for test setups.
  """
  @spec put_strategy(module()) :: :ok
  def put_strategy(module) when is_atom(module) do
    :persistent_term.put(@persistent_term_key, module)
  end

  @doc """
  Decides monitor status given a rolling per-worker history and
  sensitivity options. Delegates to the active strategy.

  `history` is a map keyed by worker name with values of sample lists
  (newest first). `opts` typically carries `:trusted_workers`,
  `:confirmation_window`, `:regions_required`, `:count_threshold`.
  """
  @spec decide(String.t(), map(), keyword()) ::
          {Uptrack.Monitoring.Consensus.Strategy.status(), map()}
  def decide(monitor_id, history, opts \\ []) do
    strategy().decide(monitor_id, history, opts)
  end
end
