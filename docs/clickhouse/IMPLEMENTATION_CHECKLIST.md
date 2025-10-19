# ClickHouse Implementation Checklist

**Target**: Complete ClickHouse integration with ResilientWriter
**Status**: Planning phase
**Next Phase**: Development

---

## Phase 1: Documentation Review (COMPLETE ✅)

Documentation is complete and committed to repository.

### Files Created
- ✅ `/docs/clickhouse/README.md` - Documentation index
- ✅ `/docs/clickhouse/ch_vs_ecto_ch.md` - Library decision guide
- ✅ `/docs/clickhouse/resilient_writer.md` - Implementation guide

### Topics Covered
- ✅ Why `ch` (not `ecto_ch`)
- ✅ What ResilientWriter is
- ✅ Batching, spooling, retry logic
- ✅ Complete implementation guide
- ✅ Production monitoring
- ✅ Troubleshooting guide

---

## Phase 2: Infrastructure Preparation

### Dependencies

```elixir
# mix.exs - Add to deps
{:ch, "~> 0.2"},           # ClickHouse HTTP client
{:jason, "~> 1.4"},        # JSON for spooling (if needed)
```

**Actions**:
- [ ] Add `:ch` dependency to `mix.exs`
- [ ] Run `mix deps.get`
- [ ] Verify `:ch` compiles without errors
- [ ] Test basic connection to ClickHouse

### NixOS Configuration

**Create** `/infra/nixos/services/resilient_writer.nix`:

```nix
# infra/nixos/services/resilient_writer.nix
{ config, pkgs, lib, ... }:

{
  # Create spool directory for ResilientWriter
  systemd.tmpfiles.rules = [
    "d /var/spool/uptrack/clickhouse 0755 uptrack uptrack - -"
  ];

  # Ensure permissions
  users.users.uptrack.extraGroups = [ "uptrack" ];
}
```

**Update** `/flake.nix`:

Add to each node's imports (all 5 nodes):
```nix
./infra/nixos/services/resilient_writer.nix
```

**Actions**:
- [ ] Create `resilient_writer.nix` NixOS module
- [ ] Add to node-a colmena config
- [ ] Add to node-b colmena config
- [ ] Add to node-c colmena config
- [ ] Add to node-india-strong colmena config
- [ ] Add to node-india-weak colmena config
- [ ] Add to all nixosConfigurations
- [ ] Deploy to test node
- [ ] Verify `/var/spool/uptrack/clickhouse` exists

### Environment Variables

**Add to `.env.example`**:

```bash
# ClickHouse Connection
CLICKHOUSE_HOST=clickhouse.internal
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default

# ResilientWriter Configuration
RESILIENT_WRITER_BATCH_SIZE=200
RESILIENT_WRITER_BATCH_TIMEOUT_MS=5000
RESILIENT_WRITER_MAX_RETRIES=10
RESILIENT_WRITER_SPOOL_DIR=/var/spool/uptrack/clickhouse
```

**Actions**:
- [ ] Update `.env.example` with ResilientWriter variables
- [ ] Update runtime.exs to read these variables
- [ ] Document environment setup per node

---

## Phase 3: ResilientWriter Implementation

### GenServer Module

**Create** `lib/uptrack/resilient_writer.ex`:

```elixir
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

  # ... see resilient_writer.md for full implementation
end
```

**Actions**:
- [ ] Create basic GenServer structure
- [ ] Implement `init/1`
- [ ] Implement `handle_cast(:write)`
- [ ] Implement batching logic
- [ ] Implement `send_batch/1`
- [ ] Implement HTTP calls to ClickHouse via `ch`
- [ ] Implement spool-to-disk on failure
- [ ] Implement retry logic with exponential backoff
- [ ] Add metrics tracking
- [ ] Add comprehensive logging

### Application Supervision Tree

**Update** `lib/uptrack/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    # ... existing children
    Uptrack.ResilientWriter,  # Add here
  ]

  opts = [strategy: :one_for_one, name: Uptrack.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Actions**:
- [ ] Add ResilientWriter to supervision tree
- [ ] Test app starts successfully
- [ ] Verify GenServer is running
- [ ] Check logs for startup

---

## Phase 4: Integration with Monitoring

### Oban Job Worker

**Update** `lib/uptrack/monitoring/check_worker.ex`:

```elixir
def perform(job) do
  result = perform_http_check(job.args)

  Uptrack.ResilientWriter.write_check_result(%{
    monitor_id: job.args["monitor_id"],
    status: result.status,
    response_time_ms: result.time_ms,
    region: node_region(),
    checked_at: DateTime.utc_now()
  })

  :ok
end
```

**Actions**:
- [ ] Identify all places that generate monitoring checks
- [ ] Add ResilientWriter calls to each
- [ ] Ensure check result format matches ClickHouse schema
- [ ] Test data flow end-to-end
- [ ] Verify no crashes on ClickHouse errors

### Test Coverage

**Create** `test/uptrack/resilient_writer_test.exs`:

```elixir
defmodule Uptrack.ResilientWriterTest do
  use ExUnit.Case

  test "accumulates rows and sends batch" do
    # Write 200 rows, verify batch sent
  end

  test "spools to disk when ClickHouse unavailable" do
    # Mock ClickHouse down, verify spool file created
  end

  test "retries with exponential backoff" do
    # Mock ClickHouse failure, verify retry timing
  end

  test "flushes spool on recovery" do
    # ClickHouse down then up, verify spool processed
  end
end
```

**Actions**:
- [ ] Create test module
- [ ] Mock ClickHouse responses
- [ ] Test batch accumulation
- [ ] Test spooling logic
- [ ] Test retry behavior
- [ ] Test recovery behavior
- [ ] Achieve 80%+ code coverage

---

## Phase 5: Monitoring & Observability

### Prometheus Metrics

**Create** `lib/uptrack/resilient_writer_metrics.ex`:

```elixir
defmodule Uptrack.ResilientWriterMetrics do
  def setup do
    :prometheus_counter.new([
      name: :clickhouse_rows_sent_total,
      help: "Total rows sent to ClickHouse"
    ])
    # ... more metrics
  end

  def record_send(count) do
    :prometheus_counter.inc(:clickhouse_rows_sent_total, count)
  end
end
```

**Actions**:
- [ ] Define Prometheus metrics
- [ ] Initialize in application startup
- [ ] Record metrics in ResilientWriter
- [ ] Export metrics endpoint (Telemetry)
- [ ] Verify metrics appear in Prometheus

### Logging

**Actions**:
- [ ] Log batch sends (info level)
- [ ] Log failures and retries (warn level)
- [ ] Log spool writes (warn level)
- [ ] Log spool recovery (info level)
- [ ] Include context in all logs (batch size, attempt count, etc.)

### Alerts

**Create** Prometheus alert rules:

```yaml
- alert: ClickHouseBatchSpooling
  expr: increase(clickhouse_rows_spooled_total[5m]) > 1000
  for: 2m
  annotations:
    summary: "ClickHouse unavailable, data spooling"

- alert: ClickHouseHighLatency
  expr: histogram_quantile(0.95, rate(clickhouse_batch_latency_ms_bucket[5m])) > 1000
  for: 5m
  annotations:
    summary: "ClickHouse batch latency high (>1s)"

- alert: ClickHouseSpoolDiskFull
  expr: node_filesystem_avail_bytes{mountpoint="/var/spool"} < 1e9
  for: 1m
  annotations:
    summary: "Spool disk low on space (<1GB free)"
```

**Actions**:
- [ ] Create alert rules file
- [ ] Test alert triggering
- [ ] Configure alert destinations (PagerDuty, Slack)
- [ ] Document alert meanings in runbook

---

## Phase 6: Development Testing

### Local Environment

**Actions**:
- [ ] Run ClickHouse in Docker: `docker run -d clickhouse/clickhouse-server`
- [ ] Update env vars to localhost
- [ ] Start Uptrack app locally
- [ ] Verify check results in ClickHouse

### Failure Scenarios

**Test failure recovery**:

1. **ClickHouse stops**
   - [ ] Stop ClickHouse service
   - [ ] Observe spool files being created
   - [ ] Check log messages
   - [ ] Restart ClickHouse
   - [ ] Verify spool flushes

2. **Network partition**
   - [ ] Block ClickHouse port: `iptables -A INPUT -p tcp --dport 8123 -j DROP`
   - [ ] Observe spool behavior
   - [ ] Unblock: `iptables -D INPUT -p tcp --dport 8123 -j DROP`
   - [ ] Verify recovery

3. **High load**
   - [ ] Generate 10K checks/sec (use load test tool)
   - [ ] Monitor batch latency
   - [ ] Check memory usage
   - [ ] Verify no data loss

### Performance Testing

**Actions**:
- [ ] Measure throughput (rows/sec)
- [ ] Measure P50, P95, P99 latencies
- [ ] Measure memory overhead
- [ ] Measure disk spool usage
- [ ] Compare with/without batching

---

## Phase 7: Staging Deployment

### Deployment Steps

**Actions**:
- [ ] Deploy to staging environment
- [ ] Run full test suite
- [ ] Monitor for 24 hours
- [ ] Verify metrics in Prometheus
- [ ] Test alert triggering
- [ ] Load test (simulate 5K monitors)
- [ ] Failure test (stop ClickHouse temporarily)

### Documentation

**Actions**:
- [ ] Create operational runbook
- [ ] Document spool location
- [ ] Document manual spool recovery
- [ ] Document metrics meaning
- [ ] Document alert responses

---

## Phase 8: Production Deployment

### Pre-Deployment

**Actions**:
- [ ] Verify staging tests pass
- [ ] Get team sign-off on design
- [ ] Create deployment plan
- [ ] Backup ClickHouse data
- [ ] Notify on-call team
- [ ] Schedule deployment window

### Deployment

**Node by node**:

1. **Germany (Primary)**
   - [ ] Deploy code
   - [ ] Verify ResilientWriter running
   - [ ] Monitor metrics for 1 hour
   - [ ] Verify check data flowing

2. **Austria (Secondary)**
   - [ ] Deploy code
   - [ ] Verify replication working
   - [ ] Monitor metrics

3. **Canada (App-only)**
   - [ ] Deploy code
   - [ ] Verify local checks sending

4. **India Strong (Replica)**
   - [ ] Deploy code
   - [ ] Verify working

5. **India Weak (App-only)**
   - [ ] Deploy code
   - [ ] Verify working

### Post-Deployment

**Actions**:
- [ ] Monitor all metrics for 24 hours
- [ ] Verify no data loss
- [ ] Check spool usage (should be near 0)
- [ ] Verify batch latency expectations
- [ ] Check log volumes
- [ ] Ensure alerts working correctly

---

## Phase 9: Optimization

### Performance Tuning

**Actions**:
- [ ] Monitor real-world throughput
- [ ] Adjust batch size if needed
- [ ] Adjust batch timeout if needed
- [ ] Tune ClickHouse inserts (format, compression)
- [ ] Monitor network usage
- [ ] Measure actual latencies

### Scaling

**Actions**:
- [ ] Monitor as monitors scale to 20K
- [ ] Verify throughput requirements met
- [ ] Plan for ClickHouse capacity
- [ ] Plan for spool disk allocation

---

## Quick Reference

### Key Files to Create/Modify

| File | Action | Status |
|------|--------|--------|
| `mix.exs` | Add `:ch` dependency | [ ] |
| `lib/uptrack/resilient_writer.ex` | Create GenServer | [ ] |
| `lib/uptrack/application.ex` | Add to supervision tree | [ ] |
| `lib/uptrack/monitoring/check_worker.ex` | Add ResilientWriter call | [ ] |
| `infra/nixos/services/resilient_writer.nix` | Create NixOS module | [ ] |
| `flake.nix` | Add resilient_writer.nix to all nodes | [ ] |
| `.env.example` | Add env variables | [ ] |
| `test/uptrack/resilient_writer_test.exs` | Create tests | [ ] |

### Testing Commands

```bash
# Verify dependency
mix deps.get && mix deps.compile

# Run tests
mix test test/uptrack/resilient_writer_test.exs

# Start local ClickHouse
docker run -d -p 8123:8123 clickhouse/clickhouse-server

# Deploy to staging
colmena apply --on node-canada

# Monitor metrics
curl http://localhost:9090/prometheus/api/v1/query?query=clickhouse_rows_sent_total
```

### Troubleshooting During Development

| Issue | Solution |
|-------|----------|
| "Can't connect to ClickHouse" | Verify host/port in env vars, check firewall |
| "Spool directory not writable" | Check permissions: `chmod 755 /var/spool/uptrack/clickhouse` |
| "GenServer crashes on startup" | Review logs, check init/1 implementation |
| "Data not appearing in ClickHouse" | Check batch format matches schema, verify HTTP call |

---

## Completion Checklist

### Documentation
- [x] Architecture documented
- [x] Implementation guide written
- [x] Decision rationale explained

### Code
- [ ] Dependencies added
- [ ] GenServer implemented
- [ ] Integration complete
- [ ] Tests written and passing

### Infrastructure
- [ ] NixOS module created
- [ ] Spool directory configured
- [ ] Monitoring metrics added
- [ ] Alerts configured

### Deployment
- [ ] Staging deployment complete
- [ ] 24-hour monitoring successful
- [ ] Production deployment complete
- [ ] Team trained on operations

### Documentation Complete
- [ ] Runbook written
- [ ] Troubleshooting guide updated
- [ ] On-call documentation updated
- [ ] Team knowledge shared

---

## Next Steps

1. **Start Phase 2** - Infrastructure Preparation
   - Add `:ch` dependency
   - Create NixOS module

2. **Then Phase 3** - ResilientWriter Implementation
   - Create GenServer
   - Implement batching logic

3. **Test thoroughly** - Phase 4-6
   - Integration tests
   - Failure scenario tests
   - Performance tests

4. **Deploy gradually** - Phase 7-8
   - Staging first
   - Monitor closely
   - Production deployment

---

**Status**: Planning Complete ✅
**Next**: Begin Phase 2 Development
**Estimated Time**: 2-3 weeks for full implementation
