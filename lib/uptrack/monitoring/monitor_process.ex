defmodule Uptrack.Monitoring.MonitorProcess do
  @moduledoc """
  Dedicated GenServer for a single monitor.

  Self-schedules checks via Process.send_after. Tracks consecutive
  failures in memory. Writes results to DB (single INSERT per check).

  Checks use fresh connections per execution via CheckExecutor — no
  persistent connections. This eliminates stale connection issues and
  correctly dispatches all monitor types (HTTP, SSL, TCP, DNS, ping).

  ## Multi-Region Consensus

  Each MonitorProcess joins a pg group for its monitor ID. After each
  check, it broadcasts the result to all group members (other regions).
  When enough results arrive, consensus is computed via the pure
  Consensus module. Only the "home node" fires alerts.

  ## Pipeline (per check tick)

      check → broadcast → collect → consensus → evaluate → record → maybe_alert

  ## Elixir Principles
  - Pipeline-oriented: each step transforms state
  - Pure/impure separation: Consensus module is pure, pg/DB at boundary
  - Let it crash: connection fails → check records error, next tick retries
  - Principle of Attraction: Consensus struct owns all consensus data + logic
  """

  use GenServer

  alias Uptrack.Maintenance
  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, CheckExecutor, CheckWorker, Consensus, MonitorRegistry, Events}
  alias Uptrack.Alerting.IncidentReminder

  require Logger

  defp region, do: Application.get_env(:uptrack, :node_region, "eu")

  @consensus_timeout_ms 10_000

  defstruct [
    :monitor_id,
    :organization_id,
    :monitor,
    :interval_ms,
    :consecutive_failures,
    :confirmation_threshold,
    :incident_id,
    :vl_trace_id,
    :status,
    :last_check,
    :last_check_record,
    :last_failure_fingerprint,
    :last_failure_recorded_at,
    :soft_retry_ref,
    :down_streak_started_at,
    checking: false,
    alerted_this_streak: false,
    probe_state: :up,
    consensus: %Consensus{},
    # Rolling per-worker history of :up | :down samples (change #11 Layer 2)
    worker_history: %{},
    # Rolling history of consensus verdicts (change #11 Layer 3)
    verdict_history: [],
    # Circuit-breaker state: when true, paging is suppressed until we
    # fall below `FlapDetector.low_threshold/0`.
    flapping?: false
  ]

  # --- Client API ---

  def start_link(%Monitor{} = monitor) do
    GenServer.start_link(__MODULE__, monitor, name: MonitorRegistry.via(monitor.id))
  end

  def update_config(monitor_id, %Monitor{} = monitor) do
    GenServer.cast(MonitorRegistry.via(monitor_id), {:update_config, monitor})
  end

  def pause(monitor_id) do
    GenServer.cast(MonitorRegistry.via(monitor_id), :pause)
  end

  def resume(monitor_id) do
    GenServer.cast(MonitorRegistry.via(monitor_id), :resume)
  end

  # --- Init ---

  @impl true
  def init(%Monitor{} = monitor) do
    # Join pg group for cross-region result broadcasting
    :pg.join(:monitor_checks, monitor.id, self())

    expected = expected_regions(monitor.id)
    confirmation_threshold = monitor.confirmation_threshold || 3

    # Hydrate streak/incident flags from the DB so the next UP check after a
    # restart routes through the resolve clause instead of silently leaving
    # the incident `ongoing` forever. Also pick up the incident's
    # `vl_trace_id` so mid-streak forensic events can join to the incident
    # without an extra DB roundtrip per check.
    {alerted, incident_id, trace_id, failures} =
      case Monitoring.get_ongoing_incident(monitor.id) do
        nil -> {false, nil, nil, 0}
        %{id: id, vl_trace_id: trace} -> {true, id, trace, confirmation_threshold}
      end

    state = %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      monitor: monitor,
      interval_ms: monitor.interval * 1000,
      consecutive_failures: failures,
      confirmation_threshold: confirmation_threshold,
      alerted_this_streak: alerted,
      incident_id: incident_id,
      vl_trace_id: trace_id,
      status: if(monitor.status == "active", do: :active, else: :paused),
      consensus: %Consensus{expected_regions: expected}
    }

    # First check runs quickly (1-3s jitter) so the user sees results immediately.
    # Subsequent checks use the full interval.
    schedule_check(:rand.uniform(2000) + 1000)

    Logger.debug("MonitorProcess started: #{monitor.name} (#{monitor.id}) region=#{region()}")
    {:ok, state}
  end

  # --- Check scheduling ---

  @impl true
  def handle_info(:check, %{status: :paused} = state) do
    schedule_check(state.interval_ms)
    {:noreply, state}
  end

  # Skip if previous check is still running (prevents cascade on slow targets)
  def handle_info(:check, %{status: :active, checking: true} = state) do
    Logger.debug("MonitorProcess #{state.monitor_id}: skipping tick (previous check still running)")
    schedule_check(state.interval_ms)
    {:noreply, state}
  end

  # Fire check — fresh connection per check via CheckExecutor
  def handle_info(:check, %{status: :active, checking: false} = state) do
    schedule_check(state.interval_ms)

    parent = self()
    monitor = state.monitor

    Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
      result = try do
        CheckExecutor.execute(monitor)
      rescue
        e -> %{monitor_id: monitor.id, status: "down", response_time: 0,
               checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
               error_message: "Check error: #{Exception.message(e)}"}
      catch
        kind, reason -> %{monitor_id: monitor.id, status: "down", response_time: 0,
                          checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
                          error_message: "Check #{kind}: #{inspect(reason)}"}
      end
      send(parent, {:check_result, result})
    end)

    {:noreply, %{state | checking: true}}
  end

  # --- Check result + consensus ---

  # Receive async check result from local check. Layer 1 SOFT/HARD
  # state machine absorbs single-packet DOWN flaps before they reach
  # the coordinator — only confirmed DOWN (same probe retries and
  # still fails) gets broadcast.
  def handle_info({:check_result, result}, state) do
    state = apply_probe_state(state, result)
    {:noreply, state}
  end

  # Fast-retry fired after a SOFT DOWN. Re-run the check via
  # CheckExecutor and route the result back through handle_info so the
  # SOFT/HARD transitions apply uniformly.
  def handle_info(:soft_retry, %{status: :active, monitor: monitor} = state) do
    parent = self()

    Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
      result =
        try do
          CheckExecutor.execute(monitor)
        rescue
          e ->
            %{
              monitor_id: monitor.id,
              status: "down",
              response_time: 0,
              checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
              error_message: "Retry error: #{Exception.message(e)}"
            }
        catch
          kind, reason ->
            %{
              monitor_id: monitor.id,
              status: "down",
              response_time: 0,
              checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
              error_message: "Retry #{kind}: #{inspect(reason)}"
            }
        end

      send(parent, {:check_result, result})
    end)

    {:noreply, %{state | soft_retry_ref: nil}}
  end

  # Ignore :soft_retry when we're no longer active (paused/terminating).
  def handle_info(:soft_retry, state), do: {:noreply, %{state | soft_retry_ref: nil}}

  # Layer 1: SOFT/HARD probe-state transitions. Returns updated state.
  # `check_result` is the raw result map coming off CheckExecutor.
  defp apply_probe_state(state, %{status: "down"} = result) do
    case state.probe_state do
      :up ->
        # First failure — schedule 5s retry, don't broadcast yet.
        ref = Process.send_after(self(), :soft_retry, 5_000)

        %{
          state
          | probe_state: :soft_down,
            soft_retry_ref: ref,
            checking: false,
            last_check_record: struct(Uptrack.Monitoring.MonitorCheck, result)
        }

      :soft_down ->
        # Retry also failed — confirm HARD down, fall through to full
        # consensus handling.
        state = %{state | probe_state: :down, soft_retry_ref: nil}
        process_confirmed_result(state, result)

      :down ->
        # Already confirmed down; treat subsequent DOWN checks as
        # normal cycles so consensus keeps ticking.
        process_confirmed_result(state, result)
    end
  end

  defp apply_probe_state(state, %{status: "up"} = result) do
    if state.soft_retry_ref, do: Process.cancel_timer(state.soft_retry_ref)
    state = %{state | probe_state: :up, soft_retry_ref: nil}
    process_confirmed_result(state, result)
  end

  defp apply_probe_state(state, _result), do: %{state | checking: false}

  # Path for results that HAVE cleared Layer 1 — add to consensus +
  # broadcast + try to decide.
  defp process_confirmed_result(state, result) do
    # Cache the local check immediately for UI responsiveness. Consensus
    # can drop the cycle (e.g. remote workers offline post-restart) in
    # which case record_result never runs. The cache is UI-only —
    # record_result overwrites with the full consensus verdict when it
    # fires.
    Uptrack.Cache.put_latest_check(
      state.monitor_id,
      %{
        status: result.status,
        response_time: Map.get(result, :response_time, 0),
        checked_at: Map.get(result, :checked_at, DateTime.utc_now())
      },
      state.monitor.interval
    )

    consensus = Consensus.add_result(state.consensus, region(), result)
    broadcast_to_group(state.monitor_id, region(), result)
    consensus = maybe_start_timer(consensus)

    state
    |> Map.put(:consensus, consensus)
    |> Map.put(:checking, false)
    |> try_consensus()
  end

  # Receive result from another region via pg
  def handle_info({:region_result, region, result}, state) do
    consensus = Consensus.add_result(state.consensus, region, result)
    consensus = maybe_start_timer(consensus)
    state = %{state | consensus: consensus}
    {:noreply, try_consensus(state)}
  end

  # Consensus timeout — evaluate with partial results if we have a majority,
  # otherwise log and drop the cycle (no verdict, no alert).
  def handle_info(:consensus_timeout, state) do
    consensus = Consensus.timeout(state.consensus)
    state = %{state | consensus: consensus}

    if Consensus.enough_results?(consensus) do
      {:noreply, try_consensus(state)}
    else
      Logger.info(
        "MonitorProcess #{state.monitor_id}: consensus timeout with insufficient data (#{Consensus.result_count(consensus)}/#{consensus.expected_regions} regions) — dropping cycle"
      )

      {:noreply, %{state | consensus: Consensus.reset(consensus)}}
    end
  end

  # Catch-all for unexpected messages (Task :DOWN, etc.)
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Config updates ---

  @impl true
  def handle_cast({:update_config, %Monitor{} = monitor}, state) do
    {:noreply, %{state |
      monitor: monitor,
      interval_ms: monitor.interval * 1000,
      confirmation_threshold: monitor.confirmation_threshold || 3
    }}
  end

  # Sent by the Task.Supervisor child that created the incident, so
  # subsequent mid-streak forensic events can carry the trace_id.
  def handle_cast({:set_incident_context, incident_id, vl_trace_id}, state) do
    {:noreply, %{state | incident_id: incident_id, vl_trace_id: vl_trace_id}}
  end

  def handle_cast(:pause, state) do
    Logger.debug("MonitorProcess paused: #{state.monitor_id}")
    {:noreply, %{state | status: :paused}}
  end

  def handle_cast(:resume, state) do
    Logger.debug("MonitorProcess resumed: #{state.monitor_id}")
    {:noreply, %{state | status: :active}}
  end

  # --- Terminate ---

  @impl true
  def terminate(_reason, state) do
    cancel_consensus_timer(state.consensus)
    :ok
  end

  # --- Consensus Pipeline ---

  # Per-cycle consensus funnel: when all (or majority-at-timeout)
  # regions have reported, commit this cycle's samples to the rolling
  # per-worker history and decide the monitor's status via the
  # configured strategy (Rolling-count by default; Unanimous for
  # rollback). The old "compute"-based per-cycle vote is retained in
  # `apply_consensus` to preserve downstream fields like
  # region_results and avg_response_time for record_result.
  defp try_consensus(state) do
    if Consensus.enough_results?(state.consensus) do
      state
      |> apply_consensus()
      |> update_rolling_history()
      |> apply_strategy_decision()
      |> update_flap_state()
      |> evaluate_result()
      |> record_result()
      |> maybe_trigger_alert()
    else
      state
    end
  end

  # Push one sample per reporting region into the rolling worker history.
  # Samples are :up or :down atoms. Regions that didn't report this cycle
  # keep their existing history untouched.
  #
  # Also report each worker's agreement with the median-of-others to
  # `WorkerHealth`, which decides whether a persistently-disagreeing
  # worker should be quarantined (change #11 §4).
  defp update_rolling_history(state) do
    results = state.consensus.region_results
    ts = DateTime.utc_now()

    record_worker_agreement(results, ts)

    new_history =
      Enum.reduce(results, state.worker_history, fn
        {region, %{status: "down"}}, acc ->
          Uptrack.Monitoring.CheckHistory.push(acc, region, :down)

        {region, %{status: "up"}}, acc ->
          Uptrack.Monitoring.CheckHistory.push(acc, region, :up)

        _, acc ->
          acc
      end)

    %{state | worker_history: new_history}
  end

  # For each reporting region, determine whether it agreed with the
  # median verdict of the OTHER regions, and push the result into
  # WorkerHealth for disagreement-rate tracking.
  defp record_worker_agreement(results, _ts) when map_size(results) < 2, do: :ok

  defp record_worker_agreement(results, ts) do
    statuses = Enum.map(results, fn {region, r} -> {region, Map.get(r, :status, "up")} end)

    Enum.each(statuses, fn {region, status} ->
      others = Enum.reject(statuses, fn {r, _} -> r == region end)
      other_median = median_status(others)
      agreed? = status == other_median
      Uptrack.Monitoring.WorkerHealth.observe(region, agreed?, ts)
    end)
  end

  defp median_status(statuses) do
    down = Enum.count(statuses, fn {_, s} -> s == "down" end)
    up = length(statuses) - down
    if down > up, do: "down", else: "up"
  end

  # Ask the configured strategy for the monitor's status given the
  # rolling per-worker history. Override `state.last_check.status` with
  # the strategy's verdict so downstream (evaluate_result, record_result,
  # maybe_trigger_alert) sees the correct state.
  defp apply_strategy_decision(state) do
    monitor = state.monitor
    trusted = Uptrack.Monitoring.CheckHistory.workers(state.worker_history)

    opts = [
      trusted_workers: trusted,
      confirmation_window: monitor_field(monitor, :confirmation_window, "3m"),
      regions_required: monitor_field(monitor, :regions_required, "majority")
    ]

    {verdict, _details} = Consensus.decide(state.monitor_id, state.worker_history, opts)

    # Observability (change #11 §8). Fire-and-forget — these writes
    # never block the decision path.
    Uptrack.Metrics.Writer.write_consensus_observation(
      state.monitor_id,
      Consensus.strategy(),
      verdict
    )

    state = maybe_send_warn_alert(state, verdict)

    # Map the strategy's 4-state return to the legacy up/down that the
    # downstream incident pipeline expects. `:degraded` stays mapped to
    # "up" here because the paging pipeline only fires on `:down`; WARN
    # is already dispatched above via `maybe_send_warn_alert`.
    legacy_status =
      case verdict do
        :up -> "up"
        :down -> "down"
        :degraded -> "up"
        :insufficient_data -> Map.get(state.last_check || %{}, :status, "up")
      end

    last_check = Map.put(state.last_check || %{}, :status, legacy_status)
    verdict_sample = if legacy_status == "down", do: :down, else: :up

    %{
      state
      | last_check: last_check,
        verdict_history: [verdict_sample | state.verdict_history] |> Enum.take(21)
    }
  end

  # WARN routing for `:degraded` (change #11 §6): fire email-only once
  # per distinct degraded streak. Streak resets whenever consensus
  # returns `:up`. `warn_alert_fired?` lives on the struct via
  # Map.put/3 — not pre-defined in defstruct so no migration for
  # existing in-flight processes on deploy.
  defp maybe_send_warn_alert(state, :degraded) do
    if Map.get(state, :warn_alert_fired?) do
      state
    else
      monitor = state.monitor

      # Synthesize a transient Incident struct — WARN does not create a
      # durable incident row. The dashboard shows degraded-state via
      # the FLAPPING / monitor-status broadcast; email is informational.
      transient_incident = %Uptrack.Monitoring.Incident{
        id: Ecto.UUID.generate(),
        monitor_id: state.monitor_id,
        organization_id: state.organization_id,
        status: "ongoing",
        cause: "Partial regional outage (degraded)",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        alert_level: "warn"
      }

      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        Uptrack.Alerting.send_incident_alerts(transient_incident, monitor, level: :warn)
      end)

      Logger.info(
        "MonitorProcess #{state.monitor_id}: dispatched WARN (email-only) for degraded state"
      )

      Map.put(state, :warn_alert_fired?, true)
    end
  end

  defp maybe_send_warn_alert(state, :up), do: Map.put(state, :warn_alert_fired?, false)
  defp maybe_send_warn_alert(state, _other), do: state

  # Run the Nagios flap detector against `verdict_history`. When
  # flapping, force last_check.status to "up" so maybe_trigger_alert
  # suppresses the page — but broadcast a FLAPPING event so the
  # dashboard still shows the state.
  defp update_flap_state(state) do
    alias Uptrack.Monitoring.FlapDetector

    percent = FlapDetector.flap_percent(state.verdict_history)
    was_flapping = state.flapping?
    is_flapping = FlapDetector.flapping?(percent, was_flapping)

    # Observability: expose flap_percent as a gauge (change #11 §8).
    Uptrack.Metrics.Writer.write_flap_percent(state.monitor_id, percent)

    state =
      cond do
        is_flapping and not was_flapping ->
          Logger.info(
            "MonitorProcess #{state.monitor_id}: entering FLAPPING state (flap_percent=#{Float.round(percent, 1)})"
          )

          maybe_broadcast_flapping(state, true)
          %{state | flapping?: true}

        was_flapping and not is_flapping ->
          Logger.info(
            "MonitorProcess #{state.monitor_id}: exiting FLAPPING state (flap_percent=#{Float.round(percent, 1)})"
          )

          maybe_broadcast_flapping(state, false)
          %{state | flapping?: false}

        true ->
          state
      end

    # While flapping, suppress the DOWN signal so maybe_trigger_alert
    # doesn't fire. The monitor row on the dashboard shows FLAPPING
    # independently via the broadcast.
    if state.flapping? and Map.get(state.last_check || %{}, :status) == "down" do
      put_in(state, [Access.key(:last_check), :status], "up")
    else
      state
    end
  end

  defp maybe_broadcast_flapping(state, flapping?) do
    # Events.broadcast_monitor_flapping/2 is wired in change #11 §3.7.
    # Until the Events helper lands, log at info so meta-monitoring can
    # still detect transitions from the journal.
    if function_exported?(Events, :broadcast_monitor_flapping, 2) do
      Events.broadcast_monitor_flapping(state.monitor, flapping?)
    else
      :ok
    end
  end

  # Safe accessor for fields that existed before change #11 schema update.
  # `monitor` may be a pre-migration struct in rare race conditions.
  defp monitor_field(monitor, field, default) do
    case Map.get(monitor, field) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  # Pure: computes consensus and updates state
  defp apply_consensus(state) do
    result = Consensus.compute(state.consensus)
    cancel_consensus_timer(state.consensus)

    region_data = serialize_region_results(state.consensus.region_results)

    %{state |
      last_check: %{
        status: result,
        check_region: region(),
        region_results: region_data,
        monitor_id: state.monitor_id,
        response_time: avg_response_time(state.consensus.region_results),
        checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      consensus: Consensus.reset(state.consensus)
    }
  end

  # --- Check Pipeline (runs after consensus) ---

  defp evaluate_result(%{last_check: %{status: "up"}, alerted_this_streak: true} = state) do
    # Was down, now up — resolve incident (only on home node to avoid duplicates)
    app_nodes =
      [node() | Node.list()]
      |> Enum.filter(fn n -> n |> to_string() |> String.starts_with?("uptrack@") end)
      |> Enum.sort()

    if Consensus.home_node?(state.monitor_id, app_nodes) do
      monitor = state.monitor

      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        case Monitoring.resolve_all_ongoing_incidents(state.monitor_id) do
          {:ok, []} ->
            :ok

          {:ok, [primary | _] = resolved_all} ->
            Enum.each(resolved_all, &Events.broadcast_incident_resolved(&1, monitor))
            Uptrack.Alerting.send_resolution_alerts(primary, monitor)
            Uptrack.Alerting.notify_subscribers_resolution(primary, monitor)

            Enum.each(resolved_all, fn incident ->
              emit_lifecycle_event(:incident_resolved, monitor,
                incident_id: incident.id,
                trace_id: incident.vl_trace_id,
                occurred_at: incident.resolved_at || DateTime.utc_now(),
                region: region()
              )
            end)

          _ ->
            :ok
        end
      end)
    end

    %{
      state
      | consecutive_failures: 0,
        alerted_this_streak: false,
        incident_id: nil,
        vl_trace_id: nil,
        last_failure_fingerprint: nil,
        last_failure_recorded_at: nil
    }
  end

  defp evaluate_result(%{last_check: %{status: "up"}} = state) do
    %{
      state
      | consecutive_failures: 0,
        alerted_this_streak: false,
        vl_trace_id: nil,
        last_failure_fingerprint: nil,
        last_failure_recorded_at: nil
    }
  end

  defp evaluate_result(%{last_check: %{status: "down"}} = state) do
    %{state | consecutive_failures: state.consecutive_failures + 1}
  end

  defp evaluate_result(state), do: state

  defp record_result(%{last_check: check_attrs} = state) when is_map(check_attrs) do
    # Build a check struct for events/metrics without writing to Postgres
    check = struct(Uptrack.Monitoring.MonitorCheck, check_attrs)

    # Buffer write to VictoriaMetrics (batched for throughput)
    Uptrack.Metrics.Batcher.write(state.monitor, check)

    # Route DOWN-check forensics through Uptrack.Failures — the adapter
    # decides the durable backend (Postgres today, VictoriaLogs after
    # cutover). `maybe_emit_failure/2` handles per-monitor fingerprint
    # dedup so repeat identical failures collapse to a single event.
    state = maybe_emit_failure(state, check)

    # Cache latest check for instant API reads (no VM query needed).
    # TTL tracks the monitor's interval so high-interval monitors (SSL,
    # DNS at 3600s) don't show "Unknown" between checks.
    Uptrack.Cache.put_latest_check(
      state.monitor_id,
      %{
        status: check.status,
        response_time: check.response_time,
        checked_at: check.checked_at
      },
      state.monitor.interval
    )

    # Broadcast for real-time UI updates
    Events.broadcast_check_completed(check, state.monitor)

    # Check response time degradation on "up" checks
    if check.status == "up", do: CheckWorker.check_degradation(state.monitor, check)

    %{state | last_check_record: check}
  rescue
    e ->
      Logger.error("MonitorProcess #{state.monitor_id}: record_result error: #{Exception.message(e)}")
      state
  end

  defp record_result(state), do: state

  # --- Forensic emission (dedup + lifecycle) ---

  # 10-minute ceiling: even if the fingerprint is identical, re-emit
  # after this much time to defend against pathological long outages
  # collapsing to a single forensic event.
  @fingerprint_ceiling_seconds 600

  # DOWN checks run through the Failures pipeline; UP checks don't.
  defp maybe_emit_failure(state, %{status: "down"} = check) do
    fingerprint = Uptrack.Failures.Fingerprint.compute(check)
    now = DateTime.utc_now()

    cond do
      fingerprint_repeat?(state, fingerprint, now) ->
        state

      true ->
        event =
          Uptrack.Failures.Event.new_from_check(check, state.monitor,
            incident_id: state.incident_id,
            trace_id: trace_id_for(state),
            region: region()
          )

        Uptrack.Failures.record(event)

        %{
          state
          | last_failure_fingerprint: fingerprint,
            last_failure_recorded_at: now
        }
    end
  end

  defp maybe_emit_failure(state, _up_check), do: state

  defp fingerprint_repeat?(%{last_failure_fingerprint: nil}, _fp, _now), do: false

  defp fingerprint_repeat?(%{last_failure_fingerprint: last, last_failure_recorded_at: ts}, fp, now)
       when last == fp and not is_nil(ts) do
    DateTime.diff(now, ts) < @fingerprint_ceiling_seconds
  end

  defp fingerprint_repeat?(_state, _fp, _now), do: false

  # Pulls trace_id from in-memory state (hydrated at init/1 or set via
  # GenServer.cast({:set_incident_context, ...}) after a successful
  # create). nil is a valid value — consumers tolerate it.
  defp trace_id_for(state), do: state.vl_trace_id

  @doc """
  Emits a lifecycle event (incident_created | incident_resolved |
  incident_upgraded). Bypasses fingerprint dedup — every transition
  gets a forensic row.

  Called from the Task.Supervisor children that own incident
  create/resolve/upgrade so the caller's process stays fast.
  """
  def emit_lifecycle_event(event_type, monitor, opts)
      when event_type in [:incident_created, :incident_resolved, :incident_upgraded] do
    event = Uptrack.Failures.Event.new_lifecycle(event_type, monitor, opts)
    Uptrack.Failures.record(event)
  end

  # Home node check — only the assigned node fires alerts (pure check, impure action)
  #
  # Already alerted this streak: consider firing a "still down" reminder if
  # the monitor has reminders enabled and the next reminder is due.
  defp maybe_trigger_alert(
         %{
           consecutive_failures: f,
           confirmation_threshold: t,
           alerted_this_streak: true,
           last_check: %{status: "down"}
         } = state
       )
       when f >= t do
    case state.monitor.reminder_interval_minutes do
      nil ->
        state

      _interval ->
        app_nodes =
          [node() | Node.list()]
          |> Enum.filter(fn n -> n |> to_string() |> String.starts_with?("uptrack@") end)
          |> Enum.sort()

        if Consensus.home_node?(state.monitor_id, app_nodes) do
          monitor_id = state.monitor_id
          monitor = state.monitor

          Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
            case Monitoring.get_ongoing_incident(monitor_id) do
              nil ->
                :ok

              incident ->
                IncidentReminder.maybe_send(incident.id, monitor)
            end
          end)
        end

        state
    end
  end

  defp maybe_trigger_alert(%{consecutive_failures: f, confirmation_threshold: t, alerted_this_streak: true} = state) when f >= t do
    state
  end

  defp maybe_trigger_alert(%{consecutive_failures: f, confirmation_threshold: t} = state) when f >= t do
    # Only app nodes (not workers) can create incidents — filter to uptrack@ nodes
    app_nodes =
      [node() | Node.list()]
      |> Enum.filter(fn n -> n |> to_string() |> String.starts_with?("uptrack@") end)
      |> Enum.sort()

    cond do
      not Consensus.home_node?(state.monitor_id, app_nodes) ->
        Logger.debug("MonitorProcess #{state.monitor_id}: #{f} failures but not home node — silent")

      Maintenance.under_maintenance?(state.monitor_id, state.organization_id) ->
        Logger.info(
          "MonitorProcess #{state.monitor_id}: #{f} consecutive failures during maintenance — suppressing alert"
        )

      true ->
        Logger.info(
          "MonitorProcess #{state.monitor_id}: #{f} consecutive failures — triggering alert (home node)"
        )

        Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
          incident_attrs = %{
            monitor_id: state.monitor_id,
            organization_id: state.organization_id,
            cause: state.last_check[:error_message] || "Monitor down",
            # Progressive alert levels (change #11 §6): the initial fire
            # is always :page. :critical is promoted later via a
            # follow-up worker when the incident is sustained >10 min.
            alert_level: "page"
          }

          handle_incident_dispatch(incident_attrs, state)
        end)
    end

    %{state | alerted_this_streak: true, down_streak_started_at: DateTime.utc_now()}
  end

  defp maybe_trigger_alert(state), do: state

  # Creates the incident or upgrades an existing degradation incident in place.
  defp handle_incident_dispatch(incident_attrs, state) do
    case Monitoring.get_ongoing_incident(state.monitor_id) do
      %{cause: cause} = existing when is_binary(cause) ->
        if String.starts_with?(cause, "Response time degradation") do
          upgrade_degradation(existing, incident_attrs, state)
        else
          Logger.info(
            "MonitorProcess #{state.monitor_id}: incident already ongoing — suppressing duplicate alert"
          )
        end

      _ ->
        create_new_incident(incident_attrs, state)
    end
  end

  defp create_new_incident(incident_attrs, state) do
    case Monitoring.create_incident(incident_attrs) do
      {:ok, incident} ->
        Events.broadcast_incident_created(incident, state.monitor)
        Uptrack.Alerting.send_incident_alerts(incident, state.monitor)
        Uptrack.Alerting.notify_subscribers_incident(incident, state.monitor)

        # Back-populate the incident context into the owning MonitorProcess
        # so mid-streak forensic events carry `trace_id`. This runs inside
        # a Task — we cast to the registered process, not `self()`.
        GenServer.cast(
          MonitorRegistry.via(state.monitor_id),
          {:set_incident_context, incident.id, incident.vl_trace_id}
        )

        emit_lifecycle_event(:incident_created, state.monitor,
          incident_id: incident.id,
          trace_id: incident.vl_trace_id,
          error_message: incident.cause,
          region: region()
        )

      {:error, :already_ongoing} ->
        Logger.info(
          "MonitorProcess #{state.monitor_id}: incident already ongoing — suppressing duplicate alert"
        )

      {:error, reason} ->
        Logger.error(
          "MonitorProcess #{state.monitor_id}: failed to create incident: #{inspect(reason)}"
        )
    end
  end

  defp upgrade_degradation(incident, incident_attrs, state) do
    case Monitoring.upgrade_incident_to_down(incident, incident_attrs[:cause]) do
      {:ok, upgraded} ->
        Logger.info(
          "MonitorProcess #{state.monitor_id}: upgraded degradation incident #{incident.id} to hard down"
        )

        Events.broadcast_incident_updated(upgraded, state.monitor)
        Uptrack.Alerting.send_incident_update_alerts(upgraded, state.monitor)

        emit_lifecycle_event(:incident_upgraded, state.monitor,
          incident_id: upgraded.id,
          trace_id: upgraded.vl_trace_id,
          error_message: upgraded.cause,
          region: region()
        )

      {:error, reason} ->
        Logger.error(
          "MonitorProcess #{state.monitor_id}: failed to upgrade degradation incident: #{inspect(reason)}"
        )
    end
  end

  # --- Impure Boundaries ---

  # Broadcast check result to all pg group members (other regions)
  defp broadcast_to_group(monitor_id, region, result) do
    :pg.get_members(:monitor_checks, monitor_id)
    |> Kernel.--([self()])
    |> Enum.each(&send(&1, {:region_result, region, result}))
  end

  # Start consensus timeout timer on first result
  defp maybe_start_timer(%Consensus{timer: nil} = c) do
    timer = Process.send_after(self(), :consensus_timeout, @consensus_timeout_ms)
    %{c | timer: timer}
  end

  defp maybe_start_timer(c), do: c

  # Cancel timer (called on consensus completion or terminate)
  defp cancel_consensus_timer(%Consensus{timer: nil}), do: :ok

  defp cancel_consensus_timer(%Consensus{timer: ref}) do
    Process.cancel_timer(ref)
    :ok
  end

  defp schedule_check(delay_ms) do
    Process.send_after(self(), :check, delay_ms)
  end

  # How many regions have processes for this monitor?
  # Uses pg group membership count, minimum 1 (this node)
  defp expected_regions(monitor_id) do
    case :pg.get_members(:monitor_checks, monitor_id) do
      members when is_list(members) -> max(length(members), 1)
      _ -> 1
    end
  end

  # Average response time across all region results
  defp avg_response_time(region_results) when map_size(region_results) == 0, do: 0

  defp avg_response_time(region_results) do
    {sum, count} =
      Enum.reduce(region_results, {0, 0}, fn {_region, result}, {sum, count} ->
        rt = Map.get(result, :response_time, 0)
        {sum + rt, count + 1}
      end)

    if count > 0, do: div(sum, count), else: 0
  end

  # Serialize region results to a JSON-safe map for DB storage
  # Input: %{"eu" => %{status: "up", response_time: 42, ...}, ...}
  # Output: %{"eu" => %{"status" => "up", "response_time" => 42}, ...}
  defp serialize_region_results(region_results) do
    Map.new(region_results, fn {region, result} ->
      {to_string(region), %{
        "status" => Map.get(result, :status, "unknown"),
        "response_time" => Map.get(result, :response_time, 0)
      }}
    end)
  end

end
