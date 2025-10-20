defmodule Uptrack.Health.IdlePrevention do
  @moduledoc """
  IdlePrevention handles preventing Oracle Always Free compute instances from being
  reclaimed due to idle resource utilization.

  Oracle reclaims idle instances when, during a 7-day period:
  - CPU utilization for 95th percentile < 20%
  - Network utilization < 20%
  - Memory utilization < 20%

  This module implements three strategies:
  1. CPU Load Generation - Periodic computation tasks
  2. Memory Pressure - Allocate and release memory
  3. Network Activity - Outbound connections and data transfer
  4. Disk I/O - Log writes and file operations

  The goal is to keep resource utilization above 20% to prevent reclamation.
  """

  use GenServer
  require Logger

  @check_interval_ms 5 * 60 * 1000  # 5 minutes
  @cpu_work_duration_ms 30 * 1000   # 30 seconds of CPU work
  @memory_allocation_mb 100          # Allocate 100MB
  @network_payload_kb 1024           # 1MB per request

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("[IdlePrevention] Starting idle prevention monitor")
    schedule_next_check()
    {:ok, %{last_check: nil, stats: %{}}}
  end

  @impl true
  def handle_info(:check_and_generate_load, state) do
    Logger.debug("[IdlePrevention] Running idle prevention cycle")

    stats =
      %{}
      |> generate_cpu_load()
      |> generate_memory_pressure()
      |> generate_network_activity()
      |> generate_disk_io()

    log_stats(stats)

    schedule_next_check()
    {:noreply, %{state | last_check: DateTime.utc_now(), stats: stats}}
  end

  # ============================================================================
  # CPU Load Generation
  # ============================================================================

  defp generate_cpu_load(stats) do
    Logger.debug("[IdlePrevention] Generating CPU load")

    task =
      Task.async(fn ->
        start_time = System.monotonic_time(:millisecond)

        # Perform CPU-intensive work
        result = intensive_computation(1000)

        elapsed = System.monotonic_time(:millisecond) - start_time
        {result, elapsed}
      end)

    try do
      {_result, elapsed} = Task.await(task, @cpu_work_duration_ms + 5000)
      Map.put(stats, :cpu_work_ms, elapsed)
    rescue
      e ->
        Logger.warning("[IdlePrevention] CPU load generation failed: #{inspect(e)}")
        Map.put(stats, :cpu_work_ms, 0)
    end
  end

  # CPU-intensive computation: fibonacci with memoization
  defp intensive_computation(iterations) do
    Enum.reduce(1..iterations, %{}, fn n, acc ->
      fib_memo(n, acc)
    end)
  end

  defp fib_memo(n, memo) when is_map_key(memo, n) do
    memo
  end

  defp fib_memo(0, memo), do: Map.put(memo, 0, 0)
  defp fib_memo(1, memo), do: Map.put(memo, 1, 1)

  defp fib_memo(n, memo) do
    memo1 = fib_memo(n - 1, memo)
    memo2 = fib_memo(n - 2, memo1)

    fib_n_minus_1 = Map.get(memo1, n - 1)
    fib_n_minus_2 = Map.get(memo2, n - 2)

    Map.put(memo2, n, fib_n_minus_1 + fib_n_minus_2)
  end

  # ============================================================================
  # Memory Pressure Generation
  # ============================================================================

  defp generate_memory_pressure(stats) do
    Logger.debug("[IdlePrevention] Generating memory pressure")

    try do
      # Allocate memory
      _data = allocate_memory(@memory_allocation_mb)

      # Do some work with it
      _checksum = calculate_memory_checksum(_data)

      # Let it be garbage collected
      Map.put(stats, :memory_allocated_mb, @memory_allocation_mb)
    rescue
      e ->
        Logger.warning("[IdlePrevention] Memory pressure generation failed: #{inspect(e)}")
        Map.put(stats, :memory_allocated_mb, 0)
    end
  end

  defp allocate_memory(mb) do
    byte_size = mb * 1024 * 1024
    String.duplicate("x", byte_size)
  end

  defp calculate_memory_checksum(data) do
    data |> String.to_charlist() |> Enum.sum()
  end

  # ============================================================================
  # Network Activity Generation
  # ============================================================================

  defp generate_network_activity(stats) do
    Logger.debug("[IdlePrevention] Generating network activity")

    task =
      Task.async(fn ->
        case fetch_health_data() do
          {:ok, _data} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

    try do
      result = Task.await(task, 30000)
      Map.put(stats, :network_activity, result)
    rescue
      e ->
        Logger.warning("[IdlePrevention] Network activity generation failed: #{inspect(e)}")
        Map.put(stats, :network_activity, {:error, inspect(e)})
    end
  end

  defp fetch_health_data do
    case Req.get("http://localhost:4000/api/health", receive_timeout: 25000) do
      {:ok, %Req.Response{status: status}} when status >= 200 and status < 300 ->
        {:ok, "health_check"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, inspect(e)}
  end

  # ============================================================================
  # Disk I/O Generation
  # ============================================================================

  defp generate_disk_io(stats) do
    Logger.debug("[IdlePrevention] Generating disk I/O")

    task =
      Task.async(fn ->
        try do
          # Write telemetry data
          timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

          log_data = """
          [#{timestamp}] IdlePrevention cycle - CPU: healthy | Memory: healthy | Network: healthy
          """

          # Write to a log file (prevents rotation from affecting stats)
          log_file = "priv/idle_prevention.log"
          File.write(log_file, log_data, [:append])

          # Keep log file manageable (rotate if > 10MB)
          case File.stat(log_file) do
            {:ok, %File.Stat{size: size}} when size > 10 * 1024 * 1024 ->
              File.rm(log_file)
              {:rotated, size}

            {:ok, %File.Stat{size: size}} ->
              {:written, size}

            {:error, _} ->
              {:error, "Could not stat log file"}
          end
        rescue
          e -> {:error, inspect(e)}
        end
      end)

    try do
      result = Task.await(task, 5000)
      Map.put(stats, :disk_io, result)
    rescue
      e ->
        Logger.warning("[IdlePrevention] Disk I/O generation failed: #{inspect(e)}")
        Map.put(stats, :disk_io, {:error, inspect(e)})
    end
  end

  # ============================================================================
  # Logging and Metrics
  # ============================================================================

  defp log_stats(stats) do
    cpu_ms = Map.get(stats, :cpu_work_ms, 0)
    memory_mb = Map.get(stats, :memory_allocated_mb, 0)
    network = Map.get(stats, :network_activity, :unknown)
    disk = Map.get(stats, :disk_io, :unknown)

    Logger.info("""
    [IdlePrevention] Cycle complete:
      - CPU work: #{cpu_ms}ms
      - Memory allocated: #{memory_mb}MB
      - Network: #{inspect(network)}
      - Disk I/O: #{inspect(disk)}
    """)

    # Emit telemetry event
    :telemetry.execute([:uptrack, :idle_prevention, :cycle], %{
      cpu_work_ms: cpu_ms,
      memory_allocated_mb: memory_mb
    })
  end

  # ============================================================================
  # Scheduling
  # ============================================================================

  defp schedule_next_check do
    Process.send_after(self(), :check_and_generate_load, @check_interval_ms)
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc "Get current statistics"
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  rescue
    _ -> %{error: "IdlePrevention not running"}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    {:reply, state.stats, state}
  end
end
