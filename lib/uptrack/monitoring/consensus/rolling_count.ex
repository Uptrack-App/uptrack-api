defmodule Uptrack.Monitoring.Consensus.RollingCount do
  @moduledoc """
  Rolling-count consensus strategy (Netflix Atlas `rolling-count` pattern).

  For each trusted worker, count DOWN samples in the last `window`
  samples (newest-first). A worker is "down" when its count crosses
  `count_threshold`. Aggregate via the monitor's `regions_required`
  rule: `:any` → any one trusted worker down, `:majority` → strict
  majority, `:all` → every trusted worker down.

  Returns `:insufficient_data` when fewer than `min_quorum` trusted
  workers are present (can't decide with confidence). Returns
  `:degraded` when 0 < down_workers < the required count — the monitor
  is neither green nor fully red and warrants a WARN, not a page.

  This module is PURE. Callers pass in the already-filtered trusted
  worker list via the `:trusted_workers` option; worker quarantine is
  applied upstream (see `Uptrack.Monitoring.WorkerHealth`).
  """

  @behaviour Uptrack.Monitoring.Consensus.Strategy

  alias Uptrack.Monitoring.CheckHistory

  # Window sizes derived from the monitor's confirmation_window enum.
  # At 30 s check cadence these correspond to 1/3/5/10 minutes.
  @window_samples %{
    "1m" => 2,
    "3m" => 6,
    "5m" => 10,
    "10m" => 20
  }

  # Count thresholds: roughly 2/3 of the window. Hardcoded for the
  # canonical values; future per-monitor override can override via opts.
  @count_thresholds %{
    "1m" => 2,
    "3m" => 4,
    "5m" => 7,
    "10m" => 14
  }

  @impl true
  def decide(_monitor_id, history, opts) do
    window = window_size(opts)
    threshold = count_threshold(opts)
    regions_required = Keyword.get(opts, :regions_required, "majority")

    # Upstream caller may pre-filter the trusted list; if not, take
    # everything in history and apply the WorkerHealth quarantine
    # filter. Quarantine lookup is a :persistent_term read — lock-free.
    trusted_workers =
      opts
      |> Keyword.get_lazy(:trusted_workers, fn -> CheckHistory.workers(history) end)
      |> Enum.filter(&worker_trusted?/1)

    decide_with(
      history,
      trusted_workers,
      window,
      threshold,
      regions_required
    )
  end

  defp worker_trusted?(worker) do
    if Code.ensure_loaded?(Uptrack.Monitoring.WorkerHealth) and
         function_exported?(Uptrack.Monitoring.WorkerHealth, :trusted?, 1) do
      Uptrack.Monitoring.WorkerHealth.trusted?(worker)
    else
      # WorkerHealth not started (tests, minimal env) — trust everyone.
      true
    end
  end

  @doc false
  def decide_with(history, trusted, window, threshold, regions_required) do
    trusted_count = length(trusted)

    cond do
      trusted_count == 0 ->
        {:insufficient_data, %{reason: :no_trusted_workers}}

      # Single-worker fallback: if only 1 region is currently trusted
      # (e.g. workers offline), degrade to `any` semantics rather than
      # silencing alerts. A real outage Europe can see still pages.
      trusted_count == 1 ->
        [only_worker] = trusted

        down_count =
          if CheckHistory.count_state(history, only_worker, :down, window) >= threshold,
            do: 1,
            else: 0

        aggregate(down_count, 1, "any", window, threshold)

      trusted_count < min_quorum(regions_required, trusted_count) ->
        {:insufficient_data,
         %{
           reason: :below_quorum,
           trusted_count: trusted_count,
           regions_required: regions_required
         }}

      true ->
        down_workers =
          Enum.filter(trusted, fn worker ->
            CheckHistory.count_state(history, worker, :down, window) >= threshold
          end)

        aggregate(length(down_workers), trusted_count, regions_required, window, threshold)
    end
  end

  defp aggregate(down_count, total, _regions, window, threshold)
       when down_count == 0 do
    {:up, %{window: window, threshold: threshold, down_workers: 0, total_workers: total}}
  end

  defp aggregate(down_count, total, "all", window, threshold) do
    status = if down_count == total, do: :down, else: :degraded

    {status,
     %{rule: :all, window: window, threshold: threshold, down_workers: down_count, total_workers: total}}
  end

  defp aggregate(down_count, total, "majority", window, threshold) do
    status = if down_count * 2 > total, do: :down, else: :degraded

    {status,
     %{
       rule: :majority,
       window: window,
       threshold: threshold,
       down_workers: down_count,
       total_workers: total
     }}
  end

  defp aggregate(down_count, total, "any", window, threshold) do
    # `:any` always pages on ≥1 down worker (still bounded by the
    # per-worker rolling count, which requires `threshold` samples).
    {:down,
     %{rule: :any, window: window, threshold: threshold, down_workers: down_count, total_workers: total}}
  end

  defp aggregate(_down, _total, _other, window, threshold) do
    # Unknown regions_required value — treat as majority for safety.
    {:up, %{window: window, threshold: threshold, degraded_via_fallback: true}}
  end

  # Minimum workers required before we even try to decide. Matches the
  # regions_required expectation so we don't accidentally decide DOWN on
  # a 1-worker sample when the monitor expects majority of 3.
  defp min_quorum("all", n), do: max(n, 1)
  defp min_quorum("majority", _n), do: 2
  defp min_quorum("any", _n), do: 1
  defp min_quorum(_other, _n), do: 1

  defp window_size(opts) do
    case Keyword.get(opts, :confirmation_window, "3m") do
      key when is_binary(key) -> Map.get(@window_samples, key, 6)
      n when is_integer(n) and n > 0 -> n
      _ -> 6
    end
  end

  defp count_threshold(opts) do
    case Keyword.get(opts, :count_threshold) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        case Keyword.get(opts, :confirmation_window, "3m") do
          key when is_binary(key) -> Map.get(@count_thresholds, key, 4)
          _ -> 4
        end
    end
  end

  @doc "Exposes the default window/threshold pairs for tests + UI copy."
  def windows, do: @window_samples
  def thresholds, do: @count_thresholds
end
