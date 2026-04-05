defmodule Uptrack.Monitoring.MonitorProcess do
  @moduledoc """
  Dedicated GenServer for a single monitor.

  Self-schedules checks via Process.send_after. Tracks consecutive
  failures in memory. Writes results to DB (single INSERT per check).

  Uses CheckClient behaviour — Gun (persistent), Finch (pool), or Mock (test)
  selected via `config :uptrack, :check_client`.

  ## Pipeline (per check tick)

      do_check → evaluate_result → record_result → maybe_trigger_alert

  ## Elixir Principles
  - Pipeline-oriented: each step transforms state
  - Pure/impure separation: evaluate is pure, record/alert are at boundary
  - Let it crash: Gun crash detected via Process.monitor, reconnects
  - Behaviours: CheckClient injected via config
  """

  use GenServer

  alias Uptrack.Monitoring
  alias Uptrack.Monitoring.{Monitor, GunConnection, MonitorRegistry, Events}
  alias Uptrack.Metrics.Writer, as: MetricsWriter

  require Logger

  @check_client Application.compile_env(:uptrack, :check_client, Uptrack.Monitoring.CheckClient.Gun)

  defstruct [
    :monitor_id,
    :organization_id,
    :monitor,
    :interval_ms,
    :consecutive_failures,
    :confirmation_threshold,
    :incident_id,
    :status,
    :conn,
    :last_check,
    :last_check_record,
    checking: false,
    alerted_this_streak: false
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
    # Open check client connection (Gun: persistent, Finch: no-op, Mock: no-op)
    conn = case @check_client.open_connection(monitor) do
      {:ok, c} -> c
      {:error, reason} ->
        Logger.error("MonitorProcess #{monitor.id}: connection failed: #{inspect(reason)}")
        nil
    end

    state = %__MODULE__{
      monitor_id: monitor.id,
      organization_id: monitor.organization_id,
      monitor: monitor,
      interval_ms: monitor.interval * 1000,
      consecutive_failures: 0,
      confirmation_threshold: monitor.confirmation_threshold || 3,
      incident_id: nil,
      status: if(monitor.status == "active", do: :active, else: :paused),
      conn: conn
    }

    # Random jitter on first check to avoid thundering herd
    jitter = :rand.uniform(max(state.interval_ms, 1000))
    schedule_check(jitter)

    Logger.debug("MonitorProcess started: #{monitor.name} (#{monitor.id})")
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

  # Fire check asynchronously — GenServer never blocks
  def handle_info(:check, %{status: :active, checking: false} = state) do
    parent = self()
    monitor = state.monitor
    conn = state.conn
    check_client = @check_client

    Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
      result = try do
        check_client.check(monitor, conn)
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

    schedule_check(state.interval_ms)
    {:noreply, %{state | checking: true}}
  end

  # Receive async check result — evaluate + record + alert pipeline
  def handle_info({:check_result, result}, state) do
    state =
      %{state | last_check: result, checking: false}
      |> evaluate_result()
      |> record_result()
      |> maybe_trigger_alert()

    {:noreply, state}
  end

  # --- Gun lifecycle messages ---

  def handle_info({:gun_up, _pid, _protocol}, state) do
    Logger.debug("MonitorProcess #{state.monitor_id}: Gun connected")
    {:noreply, %{state | conn: GunConnection.connected(state.conn)}}
  end

  def handle_info({:gun_down, _pid, _protocol, _reason, _}, state) do
    Logger.debug("MonitorProcess #{state.monitor_id}: Gun disconnected (auto-reconnecting)")
    {:noreply, %{state | conn: GunConnection.disconnected(state.conn)}}
  end

  def handle_info({:gun_error, _pid, reason}, state) do
    Logger.warning("MonitorProcess #{state.monitor_id}: Gun error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info({:gun_error, _pid, _stream, reason}, state) do
    Logger.warning("MonitorProcess #{state.monitor_id}: Gun stream error: #{inspect(reason)}")
    {:noreply, state}
  end

  # Gun process crashed — reconnect
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{conn: %GunConnection{ref: conn_ref}} = state)
      when ref == conn_ref do
    Logger.warning("MonitorProcess #{state.monitor_id}: Gun process died: #{inspect(reason)}, reconnecting")
    conn = case @check_client.open_connection(state.monitor) do
      {:ok, c} -> c
      {:error, _} -> nil
    end
    {:noreply, %{state | conn: conn}}
  end

  # Catch-all for other DOWN messages
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  # Ignore other Gun messages (gun_data, gun_push, etc.)
  def handle_info({:gun_data, _pid, _stream, _fin, _data}, state) do
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

  # --- Terminate: close connection ---

  @impl true
  def terminate(_reason, state) do
    if state.conn, do: @check_client.close_connection(state.conn)
    :ok
  end

  # --- Check Pipeline (runs after async result arrives) ---

  defp evaluate_result(%{last_check: %{status: "up"}} = state) do
    %{state | consecutive_failures: 0, alerted_this_streak: false}
  end

  defp evaluate_result(%{last_check: %{status: "down"}} = state) do
    %{state | consecutive_failures: state.consecutive_failures + 1}
  end

  defp evaluate_result(state), do: state

  defp record_result(%{last_check: check_attrs} = state) when is_map(check_attrs) do
    case Monitoring.create_monitor_check(check_attrs) do
      {:ok, check} ->
        Events.broadcast_check_completed(check, state.monitor)
        MetricsWriter.write_check_result(state.monitor, check)
        %{state | last_check_record: check}

      {:error, changeset} ->
        Logger.error("MonitorProcess #{state.monitor_id}: record failed: #{inspect(changeset.errors)}")
        state
    end
  rescue
    e ->
      Logger.error("MonitorProcess #{state.monitor_id}: record_result error: #{Exception.message(e)}")
      state
  end

  defp record_result(state), do: state

  defp maybe_trigger_alert(%{consecutive_failures: f, confirmation_threshold: t, alerted_this_streak: true} = state) when f >= t do
    state
  end

  defp maybe_trigger_alert(%{consecutive_failures: f, confirmation_threshold: t} = state) when f >= t do
    Logger.info("MonitorProcess #{state.monitor_id}: #{f} consecutive failures — triggering alert")

    if state.last_check_record do
      Task.Supervisor.start_child(Uptrack.TaskSupervisor, fn ->
        Uptrack.Alerting.send_incident_alerts(state.monitor, state.last_check_record)
      end)
    end

    %{state | alerted_this_streak: true}
  end

  defp maybe_trigger_alert(state), do: state

  # --- Helpers ---

  defp schedule_check(delay_ms) do
    Process.send_after(self(), :check, delay_ms)
  end
end
