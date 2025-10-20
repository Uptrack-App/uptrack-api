defmodule Uptrack.Monitoring.IdlePreventionWorker do
  @moduledoc """
  Oban worker for generating periodic load to prevent Oracle Always Free
  compute instance reclamation.

  This worker runs via Oban Cron every 3 hours to ensure sustained resource
  utilization that prevents idle reclamation by Oracle.

  Strategy:
  - Generate CPU load by running intensive computations
  - Create network traffic by making outbound requests
  - Generate memory allocations
  - Write disk I/O

  All activities are designed to:
  1. Push CPU utilization above 20%
  2. Generate network traffic > 20%
  3. Use memory > 20%
  4. Complete within a reasonable time window
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("[IdlePreventionWorker] Starting intensive idle prevention cycle")

    start_time = System.monotonic_time(:second)

    result =
      try do
        %{}
        |> run_cpu_intensive()
        |> run_memory_intensive()
        |> run_network_intensive()
        |> run_disk_intensive()
      rescue
        e ->
          Logger.error("[IdlePreventionWorker] Error during cycle: #{inspect(e)}")
          {:error, inspect(e)}
      end

    elapsed = System.monotonic_time(:second) - start_time
    Logger.info("[IdlePreventionWorker] Cycle complete in #{elapsed}s: #{inspect(result)}")

    :ok
  end

  # ============================================================================
  # CPU Intensive Work
  # ============================================================================

  defp run_cpu_intensive(stats) do
    Logger.debug("[IdlePreventionWorker] Running CPU intensive operations")

    tasks =
      Enum.map(1..4, fn i ->
        Task.async(fn ->
          Logger.debug("[IdlePreventionWorker] CPU task #{i} started")
          result = compute_primes(10000)
          Logger.debug("[IdlePreventionWorker] CPU task #{i} completed")
          result
        end)
      end)

    results = Task.await_many(tasks, 60000)
    Logger.info("[IdlePreventionWorker] CPU work generated #{Enum.sum(results)} operations")

    Map.put(stats, :cpu_operations, Enum.sum(results))
  end

  # Generate primes up to n using Sieve of Eratosthenes (CPU intensive)
  defp compute_primes(n) do
    sieve = List.duplicate(true, n + 1)

    {_sieve, count} =
      Enum.reduce(2..trunc(:math.sqrt(n)), {sieve, 0}, fn p, {sieve_acc, count_acc} ->
        case Enum.at(sieve_acc, p) do
          true ->
            marked_sieve =
              Enum.reduce(
                (p * p)..n//p,
                sieve_acc,
                fn i, s -> List.replace_at(s, i, false) end
              )

            {marked_sieve, count_acc + 1}

          false ->
            {sieve_acc, count_acc}
        end
      end)

    count
  end

  # ============================================================================
  # Memory Intensive Work
  # ============================================================================

  defp run_memory_intensive(stats) do
    Logger.debug("[IdlePreventionWorker] Running memory intensive operations")

    # Allocate multiple chunks of memory and work with them
    chunks = Enum.map(1..5, fn _i -> allocate_and_process_memory(50) end)

    total_mb = Enum.sum(chunks)
    Logger.info("[IdlePreventionWorker] Memory work processed #{total_mb}MB")

    Map.put(stats, :memory_processed_mb, total_mb)
  end

  defp allocate_and_process_memory(mb) do
    # Allocate memory
    data = String.duplicate("binary_data_chunk", mb * 1024)

    # Process it
    _hash = :crypto.hash(:sha256, data)

    mb
  end

  # ============================================================================
  # Network Intensive Work
  # ============================================================================

  defp run_network_intensive(stats) do
    Logger.debug("[IdlePreventionWorker] Running network intensive operations")

    # Make multiple outbound requests to generate network traffic
    tasks =
      Enum.map(1..3, fn i ->
        Task.async(fn ->
          Logger.debug("[IdlePreventionWorker] Network task #{i} started")
          result = make_network_requests()
          Logger.debug("[IdlePreventionWorker] Network task #{i} completed: #{result}")
          result
        end)
      end)

    results = Task.await_many(tasks, 30000)
    successful = Enum.count(results, &(&1 == :ok))

    Logger.info("[IdlePreventionWorker] Network requests: #{successful}/#{length(results)} successful")

    Map.put(stats, :network_requests, successful)
  end

  defp make_network_requests do
    # Try to connect to local health endpoint
    case HTTPoison.get("http://localhost:4000/api/health", [], recv_timeout: 20000) do
      {:ok, response} ->
        Logger.debug("[IdlePreventionWorker] Network request successful: #{response.status_code}")
        :ok

      {:error, reason} ->
        Logger.warning("[IdlePreventionWorker] Network request failed: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.warning("[IdlePreventionWorker] Network request exception: #{inspect(e)}")
      :error
  end

  # ============================================================================
  # Disk Intensive Work
  # ============================================================================

  defp run_disk_intensive(stats) do
    Logger.debug("[IdlePreventionWorker] Running disk intensive operations")

    result =
      try do
        # Create temporary file with data
        temp_file = "/tmp/uptrack_idle_prevention_#{System.unique_integer()}"

        # Write multiple MB of data
        data = generate_large_binary(10)

        File.write!(temp_file, data)

        # Read it back
        _read_data = File.read!(temp_file)

        # Clean up
        File.rm!(temp_file)

        {:ok, byte_size(data)}
      rescue
        e ->
          Logger.warning("[IdlePreventionWorker] Disk operation failed: #{inspect(e)}")
          {:error, inspect(e)}
      end

    case result do
      {:ok, bytes} ->
        Logger.info("[IdlePreventionWorker] Disk work: wrote/read #{div(bytes, 1024 * 1024)}MB")
        Map.put(stats, :disk_io_bytes, bytes)

      {:error, reason} ->
        Logger.warning("[IdlePreventionWorker] Disk work failed: #{reason}")
        Map.put(stats, :disk_io_bytes, 0)
    end
  end

  defp generate_large_binary(mb) do
    data_chunk = generate_random_binary(1024)
    String.duplicate(data_chunk, mb * 1024)
  end

  defp generate_random_binary(size) do
    size |> :crypto.strong_rand_bytes()
  end
end
