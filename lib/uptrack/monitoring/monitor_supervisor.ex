defmodule Uptrack.Monitoring.MonitorSupervisor do
  @moduledoc """
  DynamicSupervisor managing all MonitorProcess instances.

  Each active monitor gets a dedicated GenServer that self-schedules checks.
  Follows the Discord/WhatsApp pattern: one BEAM process per long-lived entity.
  """

  use DynamicSupervisor

  alias Uptrack.Monitoring.{MonitorProcess, MonitorRegistry}

  require Logger

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 1000,
      max_seconds: 5
    )
  end

  @doc "Starts a MonitorProcess for a monitor."
  def start_monitor(monitor) do
    case DynamicSupervisor.start_child(__MODULE__, {MonitorProcess, monitor}) do
      {:ok, pid} ->
        Logger.debug("Started MonitorProcess for #{monitor.id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MonitorProcess for #{monitor.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Stops a MonitorProcess by monitor_id."
  def stop_monitor(monitor_id) do
    case MonitorRegistry.lookup(monitor_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      :error ->
        :ok
    end
  end

  @doc "Returns count of running monitor processes."
  def count do
    MonitorRegistry.count()
  end

  @doc """
  Loads and starts all active monitors on boot.

  Called from Application.start after the supervisor is up.
  Only starts monitors assigned to this node (hash partitioning).
  """
  def start_all_active do
    monitors = Uptrack.Monitoring.list_all_active_monitors()
    node_monitors = Enum.filter(monitors, &assigned_to_this_node?/1)

    Logger.info("MonitorSupervisor: starting #{length(node_monitors)}/#{length(monitors)} monitors on #{node()}")

    Enum.each(node_monitors, &start_monitor/1)
  end

  @doc "Checks if a monitor should run on this node (hash partitioning)."
  def assigned_to_this_node?(monitor) do
    nodes = app_nodes()
    node_count = length(nodes)

    if node_count <= 1 do
      true
    else
      hash = :erlang.phash2(monitor.id, node_count)
      Enum.at(nodes, hash) == node()
    end
  end

  # App nodes are named `uptrack@...`. Worker nodes (`uptrack_worker@...`)
  # run their own MonitorSupervisor with the full monitor set, so they
  # must be excluded from the app-side partition.
  defp app_nodes do
    [node() | Node.list()]
    |> Enum.filter(fn n -> n |> to_string() |> String.starts_with?("uptrack@") end)
    |> Enum.sort()
  end
end
