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
    :status,
    :last_check,
    :last_check_record,
    checking: false,
    alerted_this_streak: false,
    consensus: %Consensus{}
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

    state = %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      monitor: monitor,
      interval_ms: monitor.interval * 1000,
      consecutive_failures: 0,
      confirmation_threshold: monitor.confirmation_threshold || 3,
      incident_id: nil,
      status: if(monitor.status == "active", do: :active, else: :paused),
      consensus: %Consensus{expected_regions: expected}
    }

    # Random jitter on first check to avoid thundering herd
    jitter = :rand.uniform(max(state.interval_ms, 1000))
    schedule_check(jitter)

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

  # Receive async check result from local check
  def handle_info({:check_result, result}, state) do
    # 1. Add our result to consensus
    consensus = Consensus.add_result(state.consensus, region(), result)

    # 2. Broadcast to other regions (impure boundary)
    broadcast_to_group(state.monitor_id, region(), result)

    # 3. Start timeout timer on first result
    consensus = maybe_start_timer(consensus)

    # 4. Try consensus
    state = %{state | consensus: consensus, checking: false}
    {:noreply, try_consensus(state)}
  end

  # Receive result from another region via pg
  def handle_info({:region_result, region, result}, state) do
    consensus = Consensus.add_result(state.consensus, region, result)
    state = %{state | consensus: consensus}
    {:noreply, try_consensus(state)}
  end

  # Consensus timeout — evaluate with partial results
  def handle_info(:consensus_timeout, state) do
    consensus = Consensus.timeout(state.consensus)
    state = %{state | consensus: consensus}
    {:noreply, try_consensus(state)}
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

  # Pure: checks if enough results, then applies consensus
  defp try_consensus(state) do
    if Consensus.enough_results?(state.consensus) do
      state
      |> apply_consensus()
      |> evaluate_result()
      |> record_result()
      |> maybe_trigger_alert()
    else
      state
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
      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        case Monitoring.get_ongoing_incident(state.monitor_id) do
          nil ->
            # No ongoing incident — nothing to resolve, no alerts
            :ok

          incident ->
            case Monitoring.resolve_incident(incident) do
              {:ok, resolved} ->
                Events.broadcast_incident_resolved(resolved, state.monitor)
                Uptrack.Alerting.send_resolution_alerts(resolved, state.monitor)
                Uptrack.Alerting.notify_subscribers_resolution(resolved, state.monitor)

              _ ->
                :ok
            end
        end
      end)
    end

    %{state | consecutive_failures: 0, alerted_this_streak: false, incident_id: nil}
  end

  defp evaluate_result(%{last_check: %{status: "up"}} = state) do
    %{state | consecutive_failures: 0, alerted_this_streak: false}
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

    # Cache latest check for instant API reads (no VM query needed)
    Uptrack.Cache.put_latest_check(state.monitor_id, %{
      status: check.status,
      response_time: check.response_time,
      checked_at: check.checked_at
    })

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

    if Consensus.home_node?(state.monitor_id, app_nodes) do
      Logger.info("MonitorProcess #{state.monitor_id}: #{f} consecutive failures — triggering alert (home node)")

      # Create incident in Postgres + send alerts
      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        incident_attrs = %{
          monitor_id: state.monitor_id,
          organization_id: state.organization_id,
          cause: state.last_check[:error_message] || "Monitor down"
        }

        case Monitoring.create_incident(incident_attrs) do
          {:ok, incident} ->
            Events.broadcast_incident_created(incident, state.monitor)
            Uptrack.Alerting.send_incident_alerts(incident, state.monitor)
            Uptrack.Alerting.notify_subscribers_incident(incident, state.monitor)

          {:error, _} ->
            Logger.error("MonitorProcess #{state.monitor_id}: failed to create incident")
        end
      end)

      %{state | alerted_this_streak: true}
    else
      Logger.debug("MonitorProcess #{state.monitor_id}: #{f} failures but not home node — silent")
      %{state | alerted_this_streak: true}
    end
  end

  defp maybe_trigger_alert(state), do: state

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
