defmodule Uptrack.Metrics.Batcher do
  @moduledoc """
  Batches VictoriaMetrics writes for throughput.

  Instead of 1 HTTP POST per check (5,000/sec at 150K monitors),
  collects metrics in a buffer and flushes every second or when
  the buffer reaches 500 items — whichever comes first.

  Single flush = 1 HTTP POST with all buffered metrics.
  """

  use GenServer

  alias Uptrack.Metrics.Writer

  @flush_interval_ms 1_000
  @max_buffer_size 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Add metric lines to the buffer. Non-blocking cast."
  def write(monitor, check) do
    GenServer.cast(__MODULE__, {:write, monitor, check})
  end

  # --- GenServer ---

  @impl true
  def init(_) do
    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl true
  def handle_cast({:write, monitor, check}, %{buffer: buffer} = state) do
    buffer = [{monitor, check} | buffer]

    if length(buffer) >= @max_buffer_size do
      flush(buffer)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: buffer}}
    end
  end

  @impl true
  def handle_info(:flush, %{buffer: []} = state) do
    schedule_flush()
    {:noreply, state}
  end

  def handle_info(:flush, %{buffer: buffer} = state) do
    flush(buffer)
    schedule_flush()
    {:noreply, %{state | buffer: []}}
  end

  defp flush(items) do
    # Delegate to Writer which handles multi-URL writes
    Enum.each(items, fn {monitor, check} ->
      Writer.write_check_result(monitor, check)
    end)
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
