defmodule Uptrack.Failures.Batcher.Shard do
  @moduledoc """
  A single Batcher shard.

  Owns one buffer and N persistent Gun connections (one per VL
  destination, currently nbg3 + nbg4). Accepts `{:write, event}`
  casts, accumulates NDJSON lines in reverse order, and flushes on
  the first of:

    * `@max_lines` (1 000) buffered
    * `@max_bytes` (1 MB) buffered
    * `@flush_interval_ms` (1 s) since last flush

  On flush, the same NDJSON payload is POSTed to every destination
  in parallel via the per-destination Gun connection (dual-write
  done app-side because the nixpkgs VL package pre-dates `vlagent`).

  Overflow discipline: when the buffer grows past `@drop_lines`
  (5 000) or `@drop_bytes` (5 MB), oldest lines are dropped and the
  `uptrack_forensic_events_dropped_total` counter is incremented.

  Gun is used rather than a pool-based client because pool size is a
  throughput ceiling. Each shard's connections are independent long-
  lived processes; reconnect is automatic.
  """

  use GenServer
  require Logger

  alias Uptrack.Failures.VlClient

  @max_lines 1_000
  @max_bytes 1_048_576
  @drop_lines 5_000
  @drop_bytes 5_242_880
  @flush_interval_ms 1_000

  # Body content type recognized by VL's /insert/jsonline endpoint.
  @insert_path "/insert/jsonline?_stream_fields=monitor_id"
  @content_type ~c"application/stream+json"

  # Headers sent with every insert. Gun sets `Connection` itself for
  # HTTP/1.1 (the `http_opts.keepalive` option drives it). Explicitly
  # setting `Connection: keep-alive` triggered a Cowlib parse crash
  # (`:cow_http_hd.token_ci_list/2`) on VL's response — leave it to Gun.
  @insert_headers [{~c"content-type", @content_type}]

  defstruct [
    :index,
    :destinations,
    :conns,
    buffer: [],
    lines: 0,
    bytes: 0,
    pending_flushes: 0,
    dropped_since_last_log: 0,
    gun_down_count: 0,
    gun_up_count: 0,
    flush_timer: nil
  ]

  # --- Client ---

  def child_spec({index, destinations}) do
    %{
      id: {__MODULE__, index},
      start: {__MODULE__, :start_link, [{index, destinations}]},
      restart: :permanent,
      shutdown: 10_000,
      type: :worker
    }
  end

  def start_link({index, destinations}) do
    name = :"Elixir.Uptrack.Failures.Batcher.Shard.#{index}"
    GenServer.start_link(__MODULE__, {index, destinations}, name: name)
  end

  @doc "Non-blocking enqueue of a pre-encoded NDJSON line."
  def write(shard_name, line) when is_atom(shard_name) and is_binary(line) do
    GenServer.cast(shard_name, {:write, line})
  end

  @doc "Returns a map of shard counters for ops + benchmarking."
  def stats(shard_name) when is_atom(shard_name) do
    GenServer.call(shard_name, :stats)
  end

  # --- GenServer ---

  @impl true
  def init({index, destinations}) do
    Process.flag(:trap_exit, true)
    state = %__MODULE__{index: index, destinations: destinations, conns: %{}}

    {:ok, schedule_flush(state), {:continue, :open_connections}}
  end

  @impl true
  def handle_continue(:open_connections, state) do
    conns =
      Map.new(state.destinations, fn {host, port} ->
        {pid, _ref} = open_conn(host, port)
        {{host, port}, pid}
      end)

    {:noreply, %{state | conns: conns}}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply,
     %{
       index: state.index,
       gun_up_count: state.gun_up_count,
       gun_down_count: state.gun_down_count,
       pending_flushes: state.pending_flushes,
       buffer_lines: state.lines,
       buffer_bytes: state.bytes,
       dropped: state.dropped_since_last_log
     }, state}
  end

  @impl true
  def handle_cast({:write, line}, state) do
    state = enqueue(state, line)

    cond do
      state.lines >= @max_lines or state.bytes >= @max_bytes ->
        {:noreply, flush(state)}

      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    state = flush(state)
    {:noreply, schedule_flush(state)}
  end

  # Gun "connection up" — ready to send. No action needed.
  def handle_info({:gun_up, _conn, _proto}, state) do
    {:noreply, %{state | gun_up_count: state.gun_up_count + 1}}
  end

  # Response headers. If non-2xx, log it; 2xx is fire-and-forget.
  def handle_info({:gun_response, conn, _sref, _fin, status, _headers}, state) do
    if status < 200 or status >= 300 do
      Logger.warning(
        "Failures.Shard #{state.index}: VL POST to #{inspect(conn_key(conn, state))} returned #{status}"
      )
    end

    {:noreply, decrement_pending(state)}
  end

  # Response body or trailers — not needed for our write path.
  def handle_info({:gun_data, _conn, _sref, _fin, _body}, state), do: {:noreply, state}
  def handle_info({:gun_trailers, _conn, _sref, _trailers}, state), do: {:noreply, state}

  # Connection down — Gun retries automatically per `:retry` option.
  # Buffered events keep accumulating; the next successful `gun_up` +
  # flush sends them.
  def handle_info({:gun_down, _conn, _proto, reason, _streams}, state) do
    Logger.debug("Failures.Shard #{state.index}: gun_down (#{inspect(reason)}); will reconnect")
    {:noreply, %{state | gun_down_count: state.gun_down_count + 1}}
  end

  # A Gun connection process crashed. Re-open a fresh one for that
  # destination. `Process.flag(:trap_exit, true)` ensures we get this.
  def handle_info({:EXIT, pid, reason}, state) do
    case Enum.find(state.conns, fn {_dest, p} -> p == pid end) do
      {{host, port} = dest, _pid} ->
        Logger.warning(
          "Failures.Shard #{state.index}: Gun #{inspect(dest)} exited #{inspect(reason)}; reopening"
        )

        {new_pid, _ref} = open_conn(host, port)
        conns = Map.put(state.conns, dest, new_pid)
        {:noreply, %{state | conns: conns}}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    for {_dest, pid} <- state.conns, is_pid(pid), do: :gun.close(pid)
    :ok
  end

  # --- private ---

  defp open_conn(host, port) do
    host_cl = String.to_charlist(host)

    {:ok, pid} =
      :gun.open(host_cl, port, %{
        protocols: [:http],
        retry: 1_000_000,
        retry_timeout: 5_000,
        # Suppress each reconnect attempt log — Gun logs every retry
        # by default and the loopback reconnect cadence is noisy.
        supervise: false,
        transport: :tcp,
        # OS-level TCP keepalive; works regardless of HTTP/1.1 intent.
        tcp_opts: [{:keepalive, true}, {:nodelay, true}],
        # HTTP/1.1 keep-alive lets Gun reuse the connection across POSTs.
        http_opts: %{version: :"HTTP/1.1", keepalive: 30_000}
      })

    ref = Process.monitor(pid)
    {pid, ref}
  end

  defp conn_key(pid, %{conns: conns}) do
    Enum.find_value(conns, fn
      {key, p} when p == pid -> key
      _ -> nil
    end) || {:unknown, :unknown}
  end

  defp enqueue(state, line) do
    size = byte_size(line)
    buffer = [line | state.buffer]
    lines = state.lines + 1
    bytes = state.bytes + size

    maybe_drop_oldest(%{state | buffer: buffer, lines: lines, bytes: bytes})
  end

  defp maybe_drop_oldest(%{lines: l, bytes: b} = state)
       when l <= @drop_lines and b <= @drop_bytes,
       do: state

  defp maybe_drop_oldest(state) do
    # buffer is in reverse chronological order (newest first). Drop
    # from the tail (oldest) until we're under both caps.
    {kept, dropped_count, dropped_bytes} = drop_from_tail(state.buffer, [], 0, 0)

    log_drop(state, dropped_count)
    Uptrack.Metrics.Writer.write_forensic_drop(dropped_count)

    %{
      state
      | buffer: kept,
        lines: state.lines - dropped_count,
        bytes: state.bytes - dropped_bytes,
        dropped_since_last_log: state.dropped_since_last_log + dropped_count
    }
  end

  # Keep removing the oldest entry (tail) until under both caps.
  defp drop_from_tail(buffer, acc, dropped_count, dropped_bytes) do
    lines = length(buffer) - dropped_count
    bytes = buffer_bytes(buffer, dropped_count)

    if lines <= @drop_lines and bytes <= @drop_bytes do
      {Enum.take(buffer, lines), dropped_count, dropped_bytes}
    else
      case :lists.reverse(buffer) do
        [oldest | _rest] ->
          acc = [oldest | acc]
          drop_from_tail(buffer, acc, dropped_count + 1, dropped_bytes + byte_size(oldest))

        [] ->
          {[], dropped_count, dropped_bytes}
      end
    end
  end

  # Fast-ish byte estimate without traversing full buffer every time.
  # Callers of drop_from_tail are rare (only on overflow).
  defp buffer_bytes(buffer, head_cut_count) do
    buffer
    |> Enum.take(length(buffer) - head_cut_count)
    |> Enum.reduce(0, fn line, acc -> acc + byte_size(line) end)
  end

  defp log_drop(state, 0), do: state

  defp log_drop(state, n) do
    total = state.dropped_since_last_log + n

    if rem(total, 1_000) < n do
      Logger.warning("Failures.Shard #{state.index}: dropped-oldest cumulative=#{total}")
    end

    state
  end

  defp flush(%{buffer: []} = state), do: state

  defp flush(state) do
    body = state.buffer |> :lists.reverse() |> IO.iodata_to_binary()

    posted =
      for {dest, conn} <- state.conns, is_pid(conn), reduce: 0 do
        acc ->
          _sref = :gun.post(conn, @insert_path, @insert_headers, body)
          _ = dest
          acc + 1
      end

    %{
      state
      | buffer: [],
        lines: 0,
        bytes: 0,
        pending_flushes: state.pending_flushes + posted
    }
  end

  defp decrement_pending(%{pending_flushes: n} = state) when n > 0,
    do: %{state | pending_flushes: n - 1}

  defp decrement_pending(state), do: state

  defp schedule_flush(state) do
    if state.flush_timer, do: Process.cancel_timer(state.flush_timer)
    timer = Process.send_after(self(), :flush, @flush_interval_ms)
    %{state | flush_timer: timer}
  end
end
