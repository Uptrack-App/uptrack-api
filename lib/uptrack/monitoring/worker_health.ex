defmodule Uptrack.Monitoring.WorkerHealth do
  @moduledoc """
  Tracks per-worker disagreement against the median of other workers
  and automatically quarantines workers whose probe stack is broken
  (wrong cacerts, TLS misconfig, asymmetric network path).

  ## Contract

  Coordinators call `observe/3` whenever a consensus cycle finishes,
  passing each worker's verdict along with the median verdict of the
  other workers for the same monitor. The GenServer buckets these
  observations by minute over a rolling 1-hour window and recomputes
  disagreement rates on a 60s timer.

  Thresholds (task §4):

    * `quarantine` when `disagreement_rate > 0.15` for 15+ minutes
    * `recover` when `disagreement_rate < 0.05` for 30+ minutes

  ## Safety cap

  If the math says more than one worker should be quarantined
  simultaneously, NONE are quarantined — it's a strong signal the
  home-region is the outlier, not the workers. A CRITICAL telemetry
  event is emitted; the cluster keeps all workers trusted until a
  human intervenes. Prefer leaking an alert to going blind.

  ## Hot path

  `trusted?/1` is the only API that hits this GenServer from the
  per-monitor decision path. It reads from `:persistent_term`, not the
  GenServer — the GenServer writes to `:persistent_term` on every
  reconcile so lookups are lock-free.
  """

  use GenServer

  require Logger

  @persistent_term_key {__MODULE__, :quarantined}
  @reconcile_interval_ms 60_000
  @window_seconds 3600
  @quarantine_threshold 0.15
  @recover_threshold 0.05
  @quarantine_sustain_seconds 15 * 60
  @recover_sustain_seconds 30 * 60

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records whether `worker` agreed with the median-of-others on a
  particular monitor/cycle. `agreed?` is a boolean; the timestamp
  defaults to now.

  Non-blocking cast — never blocks the caller.
  """
  @spec observe(any(), boolean(), DateTime.t() | nil) :: :ok
  def observe(worker, agreed?, ts \\ nil) when is_boolean(agreed?) do
    GenServer.cast(__MODULE__, {:observe, worker, agreed?, ts || DateTime.utc_now()})
  end

  @doc """
  Returns `true` if `worker` is currently trusted (i.e. NOT quarantined).
  Lock-free read from `:persistent_term`.
  """
  @spec trusted?(any()) :: boolean()
  def trusted?(worker) do
    quarantined = :persistent_term.get(@persistent_term_key, MapSet.new())
    not MapSet.member?(quarantined, worker)
  end

  @doc "Current MapSet of quarantined workers."
  @spec quarantined() :: MapSet.t()
  def quarantined do
    :persistent_term.get(@persistent_term_key, MapSet.new())
  end

  @doc """
  Force-run reconcile synchronously. Primarily for tests — production
  runs automatically on the 60s timer.
  """
  @spec reconcile() :: :ok
  def reconcile do
    GenServer.call(__MODULE__, :reconcile)
  end

  @doc "Computes the disagreement rate for a worker given raw observations. Pure — exposed for tests."
  @spec disagreement_rate([{DateTime.t(), boolean()}]) :: float()
  def disagreement_rate([]), do: 0.0

  def disagreement_rate(observations) do
    total = length(observations)
    disagreements = Enum.count(observations, fn {_ts, agreed?} -> not agreed? end)
    disagreements / total
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    # Seed an empty persistent term so `trusted?/1` returns true until
    # the first reconcile.
    :persistent_term.put(@persistent_term_key, MapSet.new())

    state = %{
      # worker => [{DateTime, agreed?}] (newest first; bounded to the window)
      observations: %{},
      # worker => %{since: DateTime | nil, until: DateTime | nil}
      states: %{},
      timer: schedule_reconcile()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:observe, worker, agreed?, ts}, state) do
    observations = Map.update(state.observations, worker, [{ts, agreed?}], fn list ->
      [{ts, agreed?} | prune_old(list, ts)]
    end)

    {:noreply, %{state | observations: observations}}
  end

  @impl true
  def handle_call(:reconcile, _from, state) do
    new_state = do_reconcile(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    state = do_reconcile(state)
    {:noreply, %{state | timer: schedule_reconcile()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- private ---

  defp do_reconcile(state) do
    now = DateTime.utc_now()

    # Prune observations outside the window for every tracked worker.
    observations =
      Map.new(state.observations, fn {worker, obs} ->
        {worker, prune_old(obs, now)}
      end)

    # For each worker, compute rate + decide should-be-quarantined.
    new_states =
      Enum.reduce(observations, state.states, fn {worker, obs}, acc ->
        rate = disagreement_rate(obs)
        worker_state = Map.get(acc, worker, %{since: nil, until: nil})
        Map.put(acc, worker, update_worker_state(worker_state, rate, now))
      end)

    # Candidates for quarantine: those whose sustained-high-disagreement
    # window has reached the 15-minute threshold.
    candidates =
      new_states
      |> Enum.filter(fn {_worker, ws} ->
        ws.since != nil and DateTime.diff(now, ws.since, :second) >= @quarantine_sustain_seconds
      end)
      |> Enum.map(&elem(&1, 0))

    # Candidates for recovery: those currently quarantined whose
    # recovery-sustained window has reached 30 minutes.
    recoveries =
      new_states
      |> Enum.filter(fn {_worker, ws} ->
        ws.until != nil and DateTime.diff(now, ws.until, :second) >= @recover_sustain_seconds
      end)
      |> Enum.map(&elem(&1, 0))

    current = :persistent_term.get(@persistent_term_key, MapSet.new())

    proposed =
      current
      |> MapSet.difference(MapSet.new(recoveries))
      |> MapSet.union(MapSet.new(candidates))

    # Safety cap: never quarantine >1 simultaneously. If the math says
    # 2+, keep the current set as-is and emit a telemetry event.
    next =
      cond do
        MapSet.size(proposed) > 1 and MapSet.size(proposed) > MapSet.size(current) ->
          Logger.warning(
            "WorkerHealth: simultaneous quarantine of multiple workers suppressed (#{inspect(MapSet.to_list(proposed))}); keeping all trusted"
          )

          :telemetry.execute(
            [:uptrack, :worker_health, :simultaneous_failure],
            %{count: MapSet.size(proposed)},
            %{candidates: MapSet.to_list(proposed)}
          )

          current

        true ->
          proposed
      end

    if next != current do
      log_transitions(current, next)
      :persistent_term.put(@persistent_term_key, next)
    end

    emit_worker_metrics(observations, next, now)

    %{state | observations: observations, states: new_states}
  end

  # Change #11 §8: emit per-worker disagreement_rate gauge +
  # quarantine gauge (0/1) on every reconcile cycle.
  defp emit_worker_metrics(observations, quarantined, _now) do
    case Uptrack.Metrics.Writer do
      module when is_atom(module) ->
        Enum.each(observations, fn {worker, obs} ->
          rate = disagreement_rate(obs)
          write_worker_gauge("uptrack_worker_disagreement_ratio", worker, rate)

          is_quarantined = if MapSet.member?(quarantined, worker), do: 1.0, else: 0.0
          write_worker_gauge("uptrack_worker_quarantined", worker, is_quarantined)
        end)
    end
  rescue
    _ -> :ok
  end

  defp write_worker_gauge(metric, worker, value) do
    ts = System.os_time(:millisecond)

    case Application.get_env(:uptrack, :victoriametrics_vminsert_url) do
      nil ->
        :ok

      url when is_binary(url) ->
        labels = %{worker: to_string(worker)}
        value_str = :io_lib.format("~.6f", [value]) |> IO.iodata_to_binary()
        body = "#{metric}{#{format_labels(labels)}} #{value_str} #{ts}"

        for target <- String.split(url, ",", trim: true) do
          _ = Req.post(String.trim(target) <> "/api/v1/import/prometheus", body: body)
        end

        :ok
    end
  rescue
    _ -> :ok
  end

  defp format_labels(labels) do
    labels
    |> Enum.map_join(",", fn {k, v} -> "#{k}=\"#{v}\"" end)
  end

  # Window-keyed state machine:
  #   rate > quarantine_threshold  → start (or keep) the `since` timer
  #   rate < recover_threshold     → start (or keep) the `until` timer
  #   between                      → don't reset, just let timers stand
  #   recovery resets on fresh disagreement
  defp update_worker_state(ws, rate, now) when rate > @quarantine_threshold do
    %{ws | since: ws.since || now, until: nil}
  end

  defp update_worker_state(ws, rate, now) when rate < @recover_threshold do
    %{ws | since: nil, until: ws.until || now}
  end

  defp update_worker_state(ws, _rate, _now) do
    # Intermediate zone — neither escalating toward quarantine nor
    # recovering. Keep whatever state we had.
    ws
  end

  defp prune_old(observations, now) do
    cutoff = DateTime.add(now, -@window_seconds, :second)

    Enum.reject(observations, fn {ts, _agreed?} ->
      DateTime.compare(ts, cutoff) == :lt
    end)
  end

  defp log_transitions(prev, next) do
    added = MapSet.difference(next, prev) |> MapSet.to_list()
    removed = MapSet.difference(prev, next) |> MapSet.to_list()

    for w <- added do
      Logger.warning("WorkerHealth: quarantined #{inspect(w)}")

      :telemetry.execute([:uptrack, :worker_health, :quarantined], %{count: 1}, %{worker: w})
    end

    for w <- removed do
      Logger.info("WorkerHealth: recovered #{inspect(w)}")
      :telemetry.execute([:uptrack, :worker_health, :recovered], %{count: 1}, %{worker: w})
    end

    :ok
  end

  defp schedule_reconcile do
    Process.send_after(self(), :reconcile, @reconcile_interval_ms)
  end

  # --- Exposed for tests ---

  @doc false
  def quarantine_threshold, do: @quarantine_threshold
  @doc false
  def recover_threshold, do: @recover_threshold
  @doc false
  def window_seconds, do: @window_seconds
end
