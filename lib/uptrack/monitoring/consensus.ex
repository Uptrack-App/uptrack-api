defmodule Uptrack.Monitoring.Consensus do
  @moduledoc """
  Pure consensus logic for multi-region check results.

  Organized around the consensus data structure — all functions
  operate on %Consensus{} and return %Consensus{} or values.
  No side effects, no DB, no messaging.

  ## Principle of Attraction
  All consensus data + logic in one module. MonitorProcess delegates
  here for consensus decisions, never reaches into the struct.

  ## Pipeline
      add_result → enough_results? → compute → reset
  """

  defstruct region_results: %{},
            expected_regions: 3,
            timer: nil,
            status: :waiting

  @type t :: %__MODULE__{
          region_results: %{atom() => map()},
          expected_regions: pos_integer(),
          timer: reference() | nil,
          status: :waiting | :ready | :timeout
        }

  # --- Pure functions ---

  @doc "Adds a region's check result."
  @spec add_result(t(), atom(), map()) :: t()
  def add_result(%__MODULE__{} = c, region, result) do
    %{c | region_results: Map.put(c.region_results, region, result)}
  end

  @doc """
  Do we have enough results to compute consensus?

  - All expected regions reported → true
  - Timeout + at least 2 results → true (partial consensus)
  - Otherwise → false (still waiting)
  """
  @spec enough_results?(t()) :: boolean()
  def enough_results?(%__MODULE__{} = c) do
    received = map_size(c.region_results)
    received >= c.expected_regions or (received >= 2 and c.status == :timeout)
  end

  @doc """
  Computes consensus: majority down = down, otherwise up.

  Returns nil if no results, "down" or "up" otherwise.
  """
  @spec compute(t()) :: String.t() | nil
  def compute(%__MODULE__{region_results: results}) when map_size(results) == 0 do
    nil
  end

  def compute(%__MODULE__{region_results: results}) do
    total = map_size(results)
    down_count = Enum.count(results, fn {_region, r} -> r.status == "down" end)

    if down_count > total / 2, do: "down", else: "up"
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
end
