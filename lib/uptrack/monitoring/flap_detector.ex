defmodule Uptrack.Monitoring.FlapDetector do
  @moduledoc """
  Nagios-style weighted state-change percentage with hysteresis.

  Operates over a bounded history of recent verdicts (21 samples,
  canonical) and reports whether the monitor is flapping so that the
  alert pipeline can suppress pages without losing dashboard signal.

  The hysteresis gap (25 pp) between `high_threshold` and
  `low_threshold` is **load-bearing** — collapsing them causes the
  detector itself to flap.

  Pure module: no DB, no GenServer, no state of its own. The caller
  (`MonitorProcess`) owns the history buffer and the boolean
  `flapping?` state.

  Algorithm:

      transitions[i]   = 1 if history[i] != history[i-1] else 0
      weight[i]        = 0.75 + 0.5 * (i / (N-2))
      flap_percent     = Σ (weight[i] * transitions[i]) / Σ weight[i] * 100

      is_flapping(flap_percent, currently_flapping?) =
        if currently_flapping?, do: flap_percent >= low_threshold
        else                  : flap_percent >  high_threshold
  """

  @default_high 50.0
  @default_low 25.0
  @default_history_size 21

  @type state :: :up | :down
  @type history :: [state()]

  @doc "Canonical history size (21). Matches Nagios `max_check_result_history`."
  def history_size, do: @default_history_size

  @doc "High-threshold default (50.0). Above this, enter flapping."
  def high_threshold, do: @default_high

  @doc "Low-threshold default (25.0). Below this, exit flapping."
  def low_threshold, do: @default_low

  @doc """
  Computes the weighted state-change percentage over `history`
  (newest-first list of `:up | :down` atoms).

  Returns 0.0 for histories shorter than 2 samples (can't measure
  transitions without a pair).
  """
  @spec flap_percent(history()) :: float()
  def flap_percent([]), do: 0.0
  def flap_percent([_only_one]), do: 0.0

  def flap_percent(history) when is_list(history) do
    # Iterate adjacent pairs. With history in newest-first order, pair
    # indices (oldest→newest) go from 0 to N-2.
    pairs = history |> Enum.reverse() |> Enum.chunk_every(2, 1, :discard)
    n_pairs = length(pairs)

    {weights_sum, weighted_sum} =
      pairs
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0.0}, fn {[prev, curr], idx}, {ws, wsum} ->
        weight = weight_for_index(idx, n_pairs)
        transition = if prev == curr, do: 0, else: 1
        {ws + weight, wsum + weight * transition}
      end)

    if weights_sum > 0.0, do: weighted_sum / weights_sum * 100.0, else: 0.0
  end

  @doc """
  Decides whether the monitor is flapping given the new `percent` and
  whether it was flapping before. Applies hysteresis to prevent the
  detector itself from flipping state.
  """
  @spec flapping?(float(), boolean(), keyword()) :: boolean()
  def flapping?(percent, was_flapping?, opts \\ [])
      when is_float(percent) and is_boolean(was_flapping?) do
    high = Keyword.get(opts, :high_threshold, @default_high)
    low = Keyword.get(opts, :low_threshold, @default_low)

    if was_flapping? do
      percent >= low
    else
      percent > high
    end
  end

  # Linear 0.75 → 1.25 weight interpolation across the transition list.
  # For a single pair (n_pairs == 1), use the average weight (1.0) so a
  # minimal history produces a sensible boundary value.
  defp weight_for_index(_idx, 1), do: 1.0

  defp weight_for_index(idx, n_pairs) do
    0.75 + 0.5 * (idx / (n_pairs - 1))
  end
end
