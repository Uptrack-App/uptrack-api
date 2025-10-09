defmodule Uptrack.ClickHouse.ResilientWriter do
  @moduledoc """
  Resilient ClickHouse writer with batching, retries, and disk spooling.

  Features:
  - Batches writes (200 rows or 1 second timeout)
  - Exponential backoff retry (5 attempts)
  - Spools to disk on persistent failure
  - Automatic flush via systemd timer

  Usage:
      ResilientWriter.write_check_result(%{
        monitor_id: uuid,
        status: "up",
        response_time_ms: 123,
        region: "us-east"
      })
  """

  use GenServer
  require Logger

  @batch_size 200
  @batch_timeout 1_000
  @max_retries 5
  @initial_backoff 200
  @spool_dir "/var/lib/uptrack/spool"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Write a check result to ClickHouse (async, batched).
  """
  def write_check_result(attrs) do
    GenServer.cast(__MODULE__, {:write, attrs})
  end

  @doc """
  Flush pending writes immediately (useful for testing).
  """
  def flush do
    GenServer.call(__MODULE__, :flush, :timer.seconds(10))
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Ensure spool directory exists
    File.mkdir_p!(@spool_dir)

    state = %{
      buffer: [],
      timer_ref: schedule_flush()
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:write, attrs}, state) do
    new_buffer = [attrs | state.buffer]

    if length(new_buffer) >= @batch_size do
      # Flush immediately if batch is full
      flush_buffer(new_buffer)
      {:noreply, %{state | buffer: [], timer_ref: reschedule_timer(state.timer_ref)}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    flush_buffer(state.buffer)
    {:reply, :ok, %{state | buffer: [], timer_ref: reschedule_timer(state.timer_ref)}}
  end

  @impl true
  def handle_info(:flush_timeout, state) do
    flush_buffer(state.buffer)
    {:noreply, %{state | buffer: [], timer_ref: schedule_flush()}}
  end

  # Private Functions

  defp schedule_flush do
    Process.send_after(self(), :flush_timeout, @batch_timeout)
  end

  defp reschedule_timer(old_ref) do
    if old_ref, do: Process.cancel_timer(old_ref)
    schedule_flush()
  end

  defp flush_buffer([]), do: :ok

  defp flush_buffer(records) do
    count = length(records)
    Logger.info("[ClickHouse] Flushing #{count} record(s)")

    case insert_with_retry(records) do
      :ok ->
        Logger.info("[ClickHouse] Successfully wrote #{count} record(s)")
        :ok

      {:error, reason} ->
        Logger.error("[ClickHouse] Failed to write after retries: #{inspect(reason)}")
        spool_to_disk(records)
    end
  end

  defp insert_with_retry(records, attempt \\ 1) do
    case insert_records(records) do
      :ok ->
        :ok

      {:error, reason} when attempt < @max_retries ->
        backoff = @initial_backoff * :math.pow(2, attempt - 1) |> round()
        Logger.warn("[ClickHouse] Attempt #{attempt}/#{@max_retries} failed: #{inspect(reason)}, retrying in #{backoff}ms")
        Process.sleep(backoff)
        insert_with_retry(records, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_records(records) do
    host = System.get_env("CLICKHOUSE_HOST", "localhost")
    port = System.get_env("CLICKHOUSE_PORT", "8123")
    database = System.get_env("CLICKHOUSE_DATABASE", "default")

    # Build INSERT query
    sql = build_insert_sql(records)

    url = "http://#{host}:#{port}/?database=#{database}"

    case Req.post(url, body: sql, headers: [{"content-type", "text/plain"}]) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      {:error, Exception.message(exception)}
  end

  defp build_insert_sql(records) do
    # Generate INSERT statement
    header = "INSERT INTO checks_raw (timestamp, monitor_id, status, response_time_ms, region, status_code, error_message) FORMAT Values"

    values =
      Enum.map_join(records, ",\n", fn record ->
        timestamp = record[:timestamp] || DateTime.utc_now()
        monitor_id = record[:monitor_id] || raise("monitor_id required")
        status = record[:status] || "unknown"
        response_time_ms = record[:response_time_ms] || 0
        region = record[:region] || System.get_env("NODE_REGION", "unknown")
        status_code = record[:status_code]
        error_message = record[:error_message]

        # Format as ClickHouse Values format
        """
        (
          '#{DateTime.to_iso8601(timestamp)}',
          '#{monitor_id}',
          '#{escape_string(status)}',
          #{response_time_ms},
          '#{escape_string(region)}',
          #{if status_code, do: status_code, else: "NULL"},
          #{if error_message, do: "'#{escape_string(error_message)}'", else: "NULL"}
        )
        """
      end)

    "#{header}\n#{values};"
  end

  defp escape_string(nil), do: ""
  defp escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end

  defp spool_to_disk(records) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = Path.join(@spool_dir, "ts=#{timestamp}.sql")

    sql = build_insert_sql(records)

    case File.write(filename, sql) do
      :ok ->
        Logger.warn("[ClickHouse] Spooled #{length(records)} record(s) to #{filename}")
        :ok

      {:error, reason} ->
        Logger.error("[ClickHouse] Failed to spool to disk: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
