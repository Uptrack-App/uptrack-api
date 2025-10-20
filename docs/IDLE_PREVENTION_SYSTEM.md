# Idle Prevention System Documentation

## Overview

The Uptrack Idle Prevention System protects Oracle Always Free compute instances from being reclaimed due to idle resource utilization. Oracle reclaims instances that maintain low resource usage for 7 consecutive days.

### Oracle Always Free Reclamation Policy

An instance is considered **idle** when during a 7-day period:
- CPU utilization (95th percentile) < 20%
- Network utilization < 20%
- Memory utilization < 20% (A1 shapes only)

This system ensures the indiastrong node stays above these thresholds.

---

## Architecture

### Components

#### 1. IdlePrevention GenServer (`lib/uptrack/health/idle_prevention.ex`)

**Purpose**: Continuous monitoring and periodic load generation every 5 minutes.

**Responsibilities**:
- CPU load generation via fibonacci computation
- Memory pressure via allocation and checksumming
- Network activity via local health checks
- Disk I/O via log file writing

**Metrics Generated**:
- CPU work duration (milliseconds)
- Memory allocated (MB)
- Network activity status
- Disk I/O results

**Telemetry Events**:
```
[:uptrack, :idle_prevention, :cycle]
  - cpu_work_ms: milliseconds of CPU computation
  - memory_allocated_mb: memory allocated in MB
```

#### 2. IdlePreventionWorker (`lib/uptrack/monitoring/idle_prevention_worker.ex`)

**Purpose**: Aggressive periodic workload generation via Oban every 3 hours.

**Responsibilities**:
- CPU-intensive prime number generation (Sieve of Eratosthenes)
- Memory-intensive binary processing and hashing
- Network-intensive outbound HTTP requests
- Disk-intensive file read/write operations

**Scheduling**: Runs at 0, 3, 6, 9, 12, 15, 18, 21 UTC (every 3 hours)

**Job Configuration**:
- Queue: `default`
- Max attempts: 3 (automatic retry)
- Unique period: 3600 seconds (prevents duplicate execution)

**Performance**:
- Expected execution time: 30-60 seconds per cycle
- Target resource utilization spike: 50-70%

---

## Load Generation Strategies

### 1. CPU Load (5-minute cycles)

**Method**: Fibonacci computation with memoization
- Computes fibonacci numbers up to iteration 1000
- Uses memoization to make computation meaningful
- Duration: ~5-30 seconds depending on system

**3-hour cycles**:
- Prime number generation using Sieve of Eratosthenes
- Generates primes up to 10,000
- Runs 4 parallel tasks
- Expected duration: 10-20 seconds per task

### 2. Memory Load (5-minute cycles)

**Method**: Memory allocation and checksumming
- Allocates 100MB of memory
- Performs checksum calculations
- Allows garbage collection to clean up

**3-hour cycles**:
- Allocates and hashes 5 x 50MB chunks
- Uses SHA256 hashing for computation
- Memory returned after use

### 3. Network Load (5-minute cycles)

**Method**: Local health check requests
- Makes request to `GET http://localhost:4000/api/health`
- Timeout: 25 seconds
- Graceful error handling

**3-hour cycles**:
- Makes 3 parallel requests
- Measures success/failure rate
- Logs details for monitoring

### 4. Disk I/O (5-minute cycles)

**Method**: Log file writing with rotation
- Writes idle prevention events to `priv/idle_prevention.log`
- Appends timestamps and status
- Automatically rotates when > 10MB

**3-hour cycles**:
- Creates temporary files with 10MB of random data
- Writes data, reads it back, deletes file
- Tests both read and write performance

---

## Configuration

### Environment Variables

```bash
# Optional: Disable idle prevention if needed
IDLE_PREVENTION_ENABLED=true

# Optional: Custom check interval (milliseconds)
IDLE_PREVENTION_CHECK_INTERVAL_MS=300000

# Optional: Custom CPU work duration (milliseconds)
IDLE_PREVENTION_CPU_WORK_DURATION_MS=30000
```

### Oban Configuration

In `config/config.exs`:

```elixir
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 300},
    {Oban.Plugins.Cron, crontab: [
      # Run monitor checks every 30 seconds
      {"*/30 * * * * *", Uptrack.Monitoring.SchedulerWorker},
      # Run idle prevention every 3 hours (aggressive load)
      {"0 */3 * * * *", Uptrack.Monitoring.IdlePreventionWorker}
    ]}
  ],
  queues: [
    default: 10,
    monitor_checks: 25,
    alerts: 5
  ]
```

---

## Monitoring

### Viewing Current Stats

```elixir
# In iex session
iex> Uptrack.Health.IdlePrevention.get_stats()
%{
  cpu_work_ms: 2450,
  memory_allocated_mb: 100,
  network_activity: :ok,
  disk_io: {:written, 45892}
}
```

### Logs

Monitor real-time activity:

```bash
# SSH into the instance
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# View live logs
tail -f /path/to/uptrack/logs/*.log | grep IdlePrevention

# Or view with journalctl
journalctl -u uptrack -f
```

### Telemetry

Metrics are emitted via Telemetry at `:telemetry.execute/3`:

```
Event: [:uptrack, :idle_prevention, :cycle]
Measurements: %{cpu_work_ms: integer, memory_allocated_mb: integer}
Metadata: %{}
```

Subscribe in monitoring system:

```elixir
:telemetry.attach(
  "idle-prevention-monitor",
  [:uptrack, :idle_prevention, :cycle],
  fn event, measurements, _metadata ->
    Logger.info("IdlePrevention cycle: #{inspect({event, measurements})}")
  end,
  nil
)
```

### Oban Dashboard

Monitor Oban jobs at: `http://localhost:4000/oban` (requires Oban Web)

Look for:
- Worker: `Uptrack.Monitoring.IdlePreventionWorker`
- Queue: `default`
- Status: `completed` (successful runs)
- Frequency: Every 3 hours

---

## Expected Behavior

### Every 5 Minutes (GenServer)

Log entries like:
```
[IdlePrevention] Running idle prevention cycle
[IdlePrevention] Generating CPU load
[IdlePrevention] Generating memory pressure
[IdlePrevention] Generating network activity
[IdlePrevention] Generating disk I/O
[IdlePrevention] Cycle complete:
  - CPU work: 2450ms
  - Memory allocated: 100MB
  - Network: :ok
  - Disk I/O: {:written, 1024000}
```

### Every 3 Hours (Oban Worker)

Log entries like:
```
[IdlePreventionWorker] Starting intensive idle prevention cycle
[IdlePreventionWorker] Running CPU intensive operations
[IdlePreventionWorker] CPU task 1 started
[IdlePreventionWorker] CPU task 1 completed
...
[IdlePreventionWorker] CPU work generated 125 operations
[IdlePreventionWorker] Running memory intensive operations
[IdlePreventionWorker] Memory work processed 250MB
[IdlePreventionWorker] Running network intensive operations
[IdlePreventionWorker] Network requests: 3/3 successful
[IdlePreventionWorker] Running disk intensive operations
[IdlePreventionWorker] Disk work: wrote/read 10MB
[IdlePreventionWorker] Cycle complete in 45s: %{...}
```

---

## Resource Impact

### CPU Usage
- 5-minute cycles: 5-30% spike for 5-30 seconds
- 3-hour cycles: 40-70% spike for 30-60 seconds
- Average impact: < 5% over 24 hours

### Memory Usage
- 5-minute cycles: +100MB temporary
- 3-hour cycles: +250MB temporary
- No permanent memory increase (garbage collected)

### Network Traffic
- 5-minute cycles: ~1KB per check
- 3-hour cycles: ~5-10KB per cycle
- ~2GB per month total (minimal)

### Disk I/O
- 5-minute cycles: ~100 bytes log writes
- 3-hour cycles: ~10MB temporary files (deleted after)
- Log file rotation at 10MB limit

---

## Troubleshooting

### System Not Generating Load

**Check 1**: Verify IdlePrevention is running

```bash
# In iex
iex> Supervisor.which_children(Uptrack.Supervisor)
# Look for Uptrack.Health.IdlePrevention
```

**Check 2**: Verify Oban is running

```bash
# In iex
iex> Oban.check_repository(Uptrack.ObanRepo)
{:ok, "Repository is ready for Oban"}
```

**Check 3**: Check logs for errors

```bash
tail -100 /path/to/uptrack/logs/*.log | grep -i error
```

### High CPU Usage

This is expected during cycles. If sustained high CPU outside cycles:
- Check for error loops in logs
- Verify CPU load generation isn't running continuously
- Consider increasing check intervals

### Network Connectivity Issues

If network requests fail:
- Verify `http://localhost:4000/api/health` is accessible
- Check firewall rules
- Verify DNS resolution working

### Disk Space Issues

If logs grow too quickly:
- Adjust rotation threshold in `IdlePrevention.generate_disk_io/1`
- Consider compressing old logs
- Monitor `/priv/idle_prevention.log`

---

## Disabling Idle Prevention

If you need to temporarily disable:

**Option 1**: Remove from supervision tree

Edit `lib/uptrack/application.ex`:
```elixir
# Comment out this line:
# Uptrack.Health.IdlePrevention,
```

**Option 2**: Remove Oban job

Edit `config/config.exs`:
```elixir
# Remove this line from crontab:
{"0 */3 * * * *", Uptrack.Monitoring.IdlePreventionWorker}
```

**Option 3**: Set environment variable (if implemented)

```bash
export IDLE_PREVENTION_ENABLED=false
```

---

## Testing

### Manual Test

```bash
# SSH into instance
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Monitor resource usage during load generation
watch -n 1 'free -h; echo; df -h; echo; top -b -n1 | head -15'

# In another terminal, check logs
tail -f /path/to/uptrack/logs/*.log
```

### Verify Oban Job

```bash
# Check if job was created
SELECT * FROM oban_jobs
WHERE worker = 'Uptrack.Monitoring.IdlePreventionWorker'
ORDER BY id DESC
LIMIT 5;

# Check completion status
SELECT id, worker, state, attempt, scheduled_at, completed_at
FROM oban_jobs
WHERE worker = 'Uptrack.Monitoring.IdlePreventionWorker';
```

---

## Maintenance

### Weekly Checks

- [ ] Verify Oban jobs are completing successfully
- [ ] Check idle prevention logs for errors
- [ ] Monitor Oracle Cloud dashboard for resource trends
- [ ] Ensure instance is not flagged for reclamation

### Monthly Checks

- [ ] Review and update load generation intensity if needed
- [ ] Analyze telemetry data for trends
- [ ] Check disk space and log rotation
- [ ] Update documentation if configuration changes

---

## Additional Resources

- [Oracle Always Free Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Oracle Compute Idle Reclamation Policy](https://docs.oracle.com/en-us/iaas/Content/Compute/References/idle_compute.htm)
- [Oban Documentation](https://hexdocs.pm/oban)
- [Elixir GenServer Guide](https://hexdocs.pm/elixir/GenServer.html)

---

**Last Updated**: 2025-10-20
**System**: Uptrack Idle Prevention v1.0
