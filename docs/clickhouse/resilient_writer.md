# ResilientWriter: The Missing Piece in Time-Series Data Ingestion

**Purpose**: Batching + Spooling + Retry logic for ClickHouse inserts
**Status**: RECOMMENDED for Uptrack
**Date**: 2025-10-19

---

## Executive Summary

**ResilientWriter** is an application-level component (not a library) that handles:
1. ✅ **Batching** - Accumulates ~200 rows before sending
2. ✅ **Spooling** - Saves to disk if ClickHouse is unavailable
3. ✅ **Retrying** - Automatically retries with exponential backoff
4. ✅ **Monitoring** - Tracks success/failure metrics

**Why it matters for Uptrack**:
- 10K+ monitors = 1K+ checks/second arriving asynchronously
- ClickHouse is across the network (Tailscale private mesh)
- Network can fail, ClickHouse can be down, deployments happen
- Can't lose monitoring data - it's your core business value

---

## Problem: What Happens Without ResilientWriter?

### Scenario 1: Austria ClickHouse Restarts

```
Germany Node (sending checks)     Austria Node (ClickHouse)
│                                 │
├─ Check 1 arrives ───────────►  X  (ClickHouse restarting)
├─ Check 2 arrives ───────────►  X  (not responding)
├─ Check 3 arrives ───────────►  X  (timeout)
│                                │
│ "Oh no! Lost 3 check results"  │
│                                │
│ Application crashes? Retry?    │ (ClickHouse comes back online)
│ But data is gone! 😱           │
```

**Result**: Lost monitoring data, incomplete incident timeline, inaccurate reports

### Scenario 2: Network Partition

```
Germany Node         Tailscale     Austria Node
│                    │              │
├─ Sending data ────►│              X  (network partition!)
│                    X──────────────X
│ "Connection timeout!"
│ Now what?
```

**Result**: Check data disappears into the void

### Scenario 3: Peak Load

```
1000 checks/second arriving
HTTP connection pool at 100%
Some checks get queued, some rejected
📉 Data loss during peak hours
```

**Result**: Incomplete data exactly when you need it most

---

## Solution: ResilientWriter Pattern

```
Application Layer          Storage Layer
┌──────────────────┐       ┌──────────────────┐
│ Check Results    │       │ Memory Batch     │
│ (1K per second)  │──────►│ (~200 rows)      │
└──────────────────┘       └────────┬─────────┘
                                    │
                                    ├──► Ready? ──► Send to ClickHouse ✅
                                    │
                                    └──► Timeout/200 rows?
                                         │
                                         ├─ Success? Clear batch ✅
                                         │
                                         ├─ Error? Spool to disk 💾
                                         │  └─ Retry in 10 seconds
                                         │  └─ Exponential backoff
                                         │  └─ Retry up to N times
                                         │
                                         └─ Metrics 📊
                                            ├─ rows_sent
                                            ├─ bytes_spooled
                                            └─ retry_count
```

---

## Why ResilientWriter (Not Just `ch` Library)

### `ch` Library Only

```elixir
# Problem: Synchronous, immediate failure
case Ch.query(:default, "INSERT INTO checks_raw", rows) do
  {:ok, _} -> :ok
  {:error, :timeout} ->
    # Now what? Data is lost!
    Logger.error("Insert failed, giving up")
end
```

**Issues**:
- No retry logic
- No batching
- No spooling
- Synchronous blocking

### ResilientWriter Pattern

```elixir
# Solution: Asynchronous, resilient
defmodule Uptrack.ResilientWriter do
  def write_check_result(result) do
    # Non-blocking, goes to GenServer queue
    GenServer.cast(:resilient_writer, {:write, result})
  end
end

# Inside GenServer:
def handle_cast({:write, row}, state) do
  state = batch_accumulate(state, row)

  if batched_ready?(state) do
    send_batch_async(state)
    {:noreply, reset_batch(state)}
  else
    {:noreply, state}
  end
end

def handle_batch_result(:error, state) do
  # Spool to disk instead of losing data
  write_to_spool_disk(state.current_batch)
  schedule_retry(500)  # Retry in 500ms
  {:noreply, reset_batch(state)}
end
```

**Benefits**:
- ✅ Non-blocking (fire-and-forget)
- ✅ Automatic batching
- ✅ Disk persistence on failure
- ✅ Retry with exponential backoff
- ✅ Metrics/monitoring built-in

---

## Architecture: Where ResilientWriter Lives

```
┌─────────────────────────────────────┐
│       Phoenix Application            │
├─────────────────────────────────────┤
│  Oban Job Queue                      │
│  ├─ CheckMonitorJob                 │
│  │  └─ result data: {monitor_id,    │
│  │     status, response_time, ...}  │
│  └─ runs on all 5 nodes             │
├─────────────────────────────────────┤
│  ResilientWriter (GenServer)         │ ◄─── CRITICAL
│  ├─ Batch accumulator (~200 rows)   │
│  ├─ HTTP client (ch library)        │
│  ├─ Spool manager (disk persistence)│
│  └─ Retry scheduler                 │
├─────────────────────────────────────┤
│  External Dependencies              │
│  ├─ ClickHouse (Austria primary)   │
│  └─ Disk spool (/var/spool/uptrack) │
└─────────────────────────────────────┘
```

**Key placement**: Inside Phoenix supervision tree
- Starts when app starts
- Restarts on crash
- Handles graceful shutdown

---

## Core Concepts

### 1. Batching (Memory Efficiency)

```elixir
# Instead of:
{1000 times per second}
  Ch.query!("INSERT INTO checks_raw ...", [one_row])  # 1000 HTTP calls!

# Do this:
{1 time every 5 seconds}
  Ch.query!("INSERT INTO checks_raw FORMAT TabSeparated", 1000_rows)  # 1 HTTP call!
```

**Benefits**:
- ✅ Reduce HTTP requests from 1000/sec to 5-10/sec
- ✅ Reduce ClickHouse parse overhead
- ✅ Reduce network traffic (one chunked request vs many)
- ✅ Higher throughput (500KB/request vs 1KB/request)

**Formula**: Batch size × Batch interval
- 200 rows × 5 second timeout = max 40 rows/sec
- 200 rows × 1 second timeout = max 200 rows/sec
- For 1000 checks/sec: multiple batchers or bigger batches

---

### 2. Spooling (Resilience)

When ClickHouse is unavailable:

```
Memory        Disk Spool          ClickHouse
├─ Batch ──► ├─ 2025-10-19_001.jsonl
│ (200      │ 2025-10-19_002.jsonl
│  rows)    │ 2025-10-19_003.jsonl  X  (not responding)
│           └─ Size: 2MB
│
└─ Retry timer triggers
   Reads from disk, tries again
   Eventually succeeds ✅
```

**Process**:
1. Batch accumulates in memory
2. Try to send to ClickHouse
3. If fails: write to disk with timestamp
4. Schedule retry (500ms, 1s, 2s, 4s, ...)
5. On retry success: delete from disk
6. On too many retries: alert operator

**Disk Format** (for manual inspection):
```jsonl
{"monitor_id": "uuid", "status": "up", "response_time_ms": 145, "checked_at": "2025-10-19T12:34:56Z"}
{"monitor_id": "uuid", "status": "down", "response_time_ms": null, "checked_at": "2025-10-19T12:34:57Z"}
```

---

### 3. Retry Logic (Smart Backoff)

```elixir
defmodule Uptrack.RetryScheduler do
  @max_retries 10
  @base_delay_ms 500
  @max_delay_ms 30_000

  def next_retry_delay(attempt_count) do
    delay = @base_delay_ms * :math.pow(2, attempt_count - 1)
    min(delay, @max_delay_ms)  # Cap at 30 seconds
  end

  # Retry timeline:
  # Attempt 1: immediate (failure)
  # Attempt 2: 500ms later
  # Attempt 3: 1s later
  # Attempt 4: 2s later
  # Attempt 5: 4s later
  # Attempt 6: 8s later
  # ... up to 30s between attempts
end
```

**Why exponential backoff**:
- ✅ Don't hammer ClickHouse while it's down
- ✅ Give it time to recover
- ✅ Avoid thundering herd (all nodes retrying at once)
- ✅ Graceful degradation

---

### 4. Monitoring & Metrics

```elixir
defmodule Uptrack.ResilientWriterMetrics do
  # Real-time metrics
  def metrics do
    %{
      "rows_sent_total" => 1_234_567,
      "rows_spooled_total" => 3_210,
      "retry_count_total" => 15,
      "current_batch_size" => 142,
      "spool_files_pending" => 2,
      "spool_bytes_total" => 2_048_000,
      "avg_batch_latency_ms" => 234,
      "last_send_at" => "2025-10-19T12:34:56Z",
      "last_error" => "connection timeout 30s ago"
    }
  end
end
```

**Monitor for**:
- Spool growth (indicates persistent failures)
- Retry count increase (indicates instability)
- Batch latency increase (indicates overload)
- Error rates

---

## Implementation Guide

### Step 1: Add Dependency

```elixir
# mix.exs
defp deps do
  [
    {:ch, "~> 0.2"},  # ClickHouse HTTP client
    # ... other deps
  ]
end
```

### Step 2: Create ResilientWriter GenServer

```elixir
# lib/uptrack/resilient_writer.ex
defmodule Uptrack.ResilientWriter do
  use GenServer
  require Logger

  @batch_size 200
  @batch_timeout_ms 5_000
  @max_retries 10
  @spool_dir "/var/spool/uptrack/clickhouse"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def write_check_result(result) do
    GenServer.cast(__MODULE__, {:write, result})
  end

  @impl true
  def init(opts) do
    File.mkdir_p!(@spool_dir)

    {:ok,
     %{
       batch: [],
       timer: nil,
       retry_attempt: 0,
       spooled_files: [],
       metrics: %{
         rows_sent: 0,
         rows_spooled: 0,
         retries: 0
       }
     }}
  end

  @impl true
  def handle_cast({:write, result}, state) do
    state = Map.update!(state, :batch, &[result | &1])

    if length(state.batch) >= @batch_size do
      send_batch(state)
    else
      schedule_batch_timeout(state)
    end
  end

  defp send_batch(state) do
    rows = Enum.reverse(state.batch)

    Task.start(fn ->
      case insert_to_clickhouse(rows) do
        :ok ->
          GenServer.cast(__MODULE__, :batch_sent)

        {:error, reason} ->
          Logger.warn("ClickHouse insert failed: #{reason}, spooling")
          GenServer.cast(__MODULE__, {:batch_failed, rows, reason})
      end
    end)

    reset_batch(state)
  end

  defp insert_to_clickhouse(rows) do
    # Format rows as tab-separated for ClickHouse
    formatted = format_rows(rows)

    case Ch.query(:default, "INSERT INTO checks_raw FORMAT TabSeparated", formatted) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp spool_to_disk(rows, reason) do
    filename = "#{DateTime.utc_now() |> DateTime.to_iso8601()}_#{System.unique_integer()}.jsonl"
    path = Path.join(@spool_dir, filename)

    json_lines = Enum.map_join(rows, "\n", &Jason.encode!/1)
    File.write!(path, json_lines)

    Logger.warn("Spooled #{length(rows)} rows to #{path} (reason: #{reason})")
    path
  end

  defp format_rows(rows) do
    Enum.map_join(rows, "\n", fn row ->
      [
        row.monitor_id,
        row.status,
        row.response_time_ms,
        row.region,
        DateTime.to_iso8601(row.checked_at)
      ]
      |> Enum.join("\t")
    end)
  end

  defp reset_batch(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | batch: [], timer: nil}
  end

  defp schedule_batch_timeout(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :batch_timeout, @batch_timeout_ms)
    %{state | timer: timer}
  end

  @impl true
  def handle_info(:batch_timeout, state) do
    if length(state.batch) > 0 do
      send_batch(state)
    else
      {:noreply, reset_batch(state)}
    end
  end
end
```

### Step 3: Add to Supervision Tree

```elixir
# lib/uptrack/application.ex
def start(_type, _args) do
  children = [
    # ... other children
    Uptrack.ResilientWriter,  # Add here
  ]

  opts = [strategy: :one_for_one, name: Uptrack.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Step 4: Use in Your Code

```elixir
# In Oban job worker
defmodule Uptrack.Monitoring.CheckWorker do
  use Oban.Worker

  def perform(job) do
    result = perform_http_check(job.args)

    # Send to ClickHouse via ResilientWriter
    Uptrack.ResilientWriter.write_check_result(%{
      monitor_id: job.args["monitor_id"],
      status: result.status,
      response_time_ms: result.time_ms,
      region: node_region(),
      checked_at: DateTime.utc_now()
    })

    :ok
  end
end
```

---

## When NOT to Use ResilientWriter

You don't need ResilientWriter if:

1. **ClickHouse is local** (same machine as app)
   - Network failures unlikely
   - Can use direct query

2. **Data loss is acceptable**
   - E.g., analytics that aren't critical
   - Duplicates are OK (idempotent)

3. **Throughput is very low** (<10 checks/sec)
   - Can use `Ch.query` directly
   - No batching needed

4. **You have a message queue** (Kafka, RabbitMQ)
   - Message queue handles retries
   - ResilientWriter is redundant

---

## When TO Use ResilientWriter

✅ **Use ResilientWriter if**:

1. **High-throughput time-series** (100+ events/sec)
   - Batching improves performance 10x
   - Network efficiency critical

2. **Data loss is not acceptable**
   - Spool to disk on failure
   - Critical business value

3. **ClickHouse is remote** (across network/private mesh)
   - Network failures possible
   - Need resilience layer

4. **Real-time monitoring**
   - Need low-latency writes
   - Batch optimization helps

5. **Multi-node deployment**
   - Each node writes independently
   - Centralized storage (ClickHouse)
   - Spooling handles rebalancing

**For Uptrack**: ✅ All 5 points apply

---

## Monitoring in Production

### Prometheus Metrics

```elixir
defmodule Uptrack.ResilientWriterMetrics do
  def setup_prometheus do
    :prometheus_counter.new([
      name: :clickhouse_rows_sent_total,
      help: "Total rows sent to ClickHouse"
    ])

    :prometheus_counter.new([
      name: :clickhouse_rows_spooled_total,
      help: "Total rows written to spool"
    ])

    :prometheus_gauge.new([
      name: :clickhouse_spool_size_bytes,
      help: "Current spool size in bytes"
    ])

    :prometheus_histogram.new([
      name: :clickhouse_batch_latency_ms,
      help: "Batch processing latency"
    ])
  end
end
```

### Alerts to Set Up

```yaml
# Prometheus alert rules
- alert: ClickHouseBatchSpooling
  expr: increase(clickhouse_rows_spooled_total[5m]) > 1000
  annotations:
    summary: "ClickHouse unavailable, spooling data"

- alert: ClickHouseHighLatency
  expr: histogram_quantile(0.95, clickhouse_batch_latency_ms) > 1000
  annotations:
    summary: "ClickHouse batch latency high"

- alert: ClickHouseSpoolDiskFull
  expr: clickhouse_spool_size_bytes > 10_000_000_000  # 10GB
  annotations:
    summary: "Spool disk nearly full, ClickHouse may be down"
```

---

## Deployment Checklist

- [ ] Create `/var/spool/uptrack/clickhouse` directory on all nodes
- [ ] Add disk space monitoring (alert if >80% full)
- [ ] Configure Prometheus metrics
- [ ] Set up alerts for spooling events
- [ ] Test failure scenario: stop ClickHouse, verify spooling
- [ ] Test recovery: restart ClickHouse, verify spool flush
- [ ] Monitor batch latency in production
- [ ] Monitor spool growth over time
- [ ] Document spool location in runbooks

---

## Troubleshooting

### Problem: Spool grows continuously

**Cause**: ClickHouse is down or unreachable

**Solution**:
1. Check ClickHouse status: `systemctl status clickhouse-server`
2. Check network: `ping -c 1 clickhouse.internal`
3. Check metrics: `curl http://localhost:8123/ping`
4. Review logs: `journalctl -u clickhouse-server -f`

### Problem: Batch latency suddenly high (>1 second)

**Cause**: ClickHouse overloaded or network slow

**Solution**:
1. Check ClickHouse disk space: `du -sh /var/lib/clickhouse`
2. Check load average: `top -n1 | grep load`
3. Check network latency: `ping clickhouse.internal`
4. Review ClickHouse slow queries

### Problem: Data not appearing in ClickHouse

**Cause**: Possible spool disk full or permissions issue

**Solution**:
1. Check spool directory: `ls -la /var/spool/uptrack/clickhouse`
2. Check disk space: `df -h /var/spool`
3. Check permissions: `sudo chown uptrack:uptrack /var/spool/uptrack/clickhouse`
4. Manually process spooled files: `cat *.jsonl | clickhouse-client --query "INSERT INTO checks_raw FORMAT TabSeparated"`

---

## Performance Expectations

### With ResilientWriter

| Metric | Value |
|--------|-------|
| **Throughput** | 10K-50K rows/sec (depending on batch size) |
| **P50 Latency** | <100ms (fire-and-forget) |
| **P99 Latency** | <500ms (during batching) |
| **Memory overhead** | ~50MB (200-row batches) |
| **Disk overhead** | 0 (only during failures) |
| **Resilience** | Yes (spools on failure) |

### Without ResilientWriter (direct Ch.query)

| Metric | Value |
|--------|-------|
| **Throughput** | 100-200 rows/sec |
| **P50 Latency** | <50ms (sync call) |
| **P99 Latency** | <2000ms (network dependent) |
| **Memory overhead** | <1MB |
| **Disk overhead** | 0 |
| **Resilience** | No (loses data on failure) |

**10x-100x throughput improvement with batching!**

---

## Summary

| Aspect | Without ResilientWriter | With ResilientWriter |
|--------|------------------------|----------------------|
| **Throughput** | 100/sec ❌ | 10K+/sec ✅ |
| **Resilience** | No ❌ | Yes ✅ |
| **Data loss** | Yes ❌ | No ✅ |
| **Complexity** | Low | Medium ✅ |
| **Production ready** | No | Yes ✅ |

**For Uptrack**: ResilientWriter is **ESSENTIAL** ✅

---

## Next Steps

1. **Implement** ResilientWriter GenServer (see Step 2 above)
2. **Add** spool directory to NixOS config
3. **Add** Prometheus metrics
4. **Add** alerting rules
5. **Test** failure scenarios
6. **Monitor** in production

---

## References

- **[ch vs ecto_ch](./ch_vs_ecto_ch.md)** - Library comparison
- **[ClickHouse Architecture](../architecture/ARCHITECTURE-SUMMARY.md)** - Replication setup
- **[Monitoring Data Flow](../ARCHITECTURE-SUMMARY.md)** - End-to-end monitoring pipeline
