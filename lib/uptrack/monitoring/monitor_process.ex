defmodule Uptrack.Monitoring.MonitorProcess do
  @moduledoc """
  Dedicated GenServer for a single monitor.

  Self-schedules checks via Process.send_after. Tracks consecutive
  failures in memory. Writes results to DB (single INSERT per check).

  Follows the Discord/WhatsApp pattern: one BEAM process per
  long-lived entity. BEAM handles millions of these efficiently.

  ## Pipeline (per check tick)

      execute_check → evaluate → record_to_db → maybe_alert → schedule_next
  """

  use GenServer

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, CheckExecutor, MonitorRegistry, Events}
  alias Uptrack.Metrics.Writer, as: MetricsWriter

  require Logger

  defstruct [
    :monitor_id,
    :organization_id,
    :monitor,
    :interval_ms,
    :consecutive_failures,
    :confirmation_threshold,
    :incident_id,
    :status
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

  # --- Callbacks ---

  @impl true
  def init(%Monitor{} = monitor) do
    state = %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      monitor: monitor,
      interval_ms: monitor.interval * 1000,
      consecutive_failures: 0,
      confirmation_threshold: monitor.confirmation_threshold || 3,
      incident_id: nil,
      status: if(monitor.status == "active", do: :active, else: :paused)
    }

    # Random jitter on first check to avoid thundering herd
    jitter = :rand.uniform(max(state.interval_ms, 1000))
    schedule_check(jitter)

    Logger.debug("MonitorProcess started: #{monitor.name} (#{monitor.id})")
    {:ok, state}
  end

  @impl true
  def handle_info(:check, %{status: :paused} = state) do
    schedule_check(state.interval_ms)
    {:noreply, state}
  end

  def handle_info(:check, %{status: :active} = state) do
    state =
      state
      |> do_check()
      |> evaluate_result()
      |> record_result()
      |> maybe_trigger_alert()

    schedule_check(state.interval_ms)
    {:noreply, state}
  catch
    kind, reason ->
      Logger.error("MonitorProcess #{state.monitor_id} check failed: #{Exception.format(kind, reason, __STACKTRACE__)}")
      schedule_check(state.interval_ms)
      {:noreply, state}
  end

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

  # --- Check Pipeline (pure-ish — DB writes at boundary) ---

  defp do_check(state) do
    check_attrs = CheckExecutor.execute(state.monitor)
    Map.put(state, :last_check, check_attrs)
  end

  defp evaluate_result(%{last_check: %{status: "up"}} = state) do
    %{state | consecutive_failures: 0}
  end

  defp evaluate_result(%{last_check: %{status: "down"}} = state) do
    %{state | consecutive_failures: state.consecutive_failures + 1}
  end

  defp evaluate_result(state), do: state

  defp record_result(%{last_check: check_attrs} = state) do
    case Monitoring.create_monitor_check(check_attrs) do
      {:ok, check} ->
        Events.broadcast_check_completed(check, state.monitor)
        MetricsWriter.write_check_result(state.monitor, check)
        %{state | last_check_record: check}

      {:error, changeset} ->
        Logger.error("MonitorProcess #{state.monitor_id}: failed to record check: #{inspect(changeset.errors)}")
        state
    end
  rescue
    e ->
      Logger.error("MonitorProcess #{state.monitor_id}: record_result error: #{Exception.message(e)}")
      state
  end

  defp maybe_trigger_alert(%{consecutive_failures: f, confirmation_threshold: t} = state) when f >= t do
    # Only alert if we just crossed the threshold (not on every subsequent failure)
    if f == t do
      Logger.info("MonitorProcess #{state.monitor_id}: #{f} consecutive failures — triggering alert")
      monitor = refresh_monitor(state.monitor_id) || state.monitor

      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        Uptrack.Alerting.send_incident_alerts(monitor, state.last_check_record)
      end)
    end

    state
  end

  defp maybe_trigger_alert(state), do: state

  # --- Helpers ---

  defp schedule_check(delay_ms) do
    Process.send_after(self(), :check, delay_ms)
  end

  defp refresh_monitor(monitor_id) do
    Monitoring.get_monitor(monitor_id)
  rescue
    _ -> nil
  end
end
