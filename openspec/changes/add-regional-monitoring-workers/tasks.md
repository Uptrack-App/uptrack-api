# Implementation Tasks: Regional Monitoring Workers

**Change ID**: `add-regional-monitoring-workers`
**Estimated effort**: 5-8 days
**Prerequisites**: `1-monitoring-infrastructure` must be deployed

---

## Phase 1: NixOS Profile Refactoring (2-3 days)

### 1.1 Create Profile Infrastructure

- [ ] Create `infra/nixos/profiles/` directory structure
- [ ] Extract common SSH/Tailscale config from `common/base.nix` into refined version
- [ ] Document profile composition pattern in `/docs/deployment/nixos-profiles.md`

### 1.2 Create Infrastructure Profile

- [ ] Create `profiles/infrastructure.nix` with PostgreSQL 17 configuration
- [ ] Add VictoriaMetrics cluster components (vmstorage, vminsert, vmselect) to profile
- [ ] Add etcd configuration to profile
- [ ] Define systemd resource limits (PostgreSQL: 2.5GB, VM: 2GB, etcd: 300MB)
- [ ] Add health check commands for each infrastructure service
- [ ] Test profile builds: `nixos-rebuild build --flake '.#infrastructure-test'`

### 1.3 Create Worker Profile

- [ ] Create `profiles/worker.nix` with Uptrack worker systemd service definition
- [ ] Configure worker to read `NODE_REGION` environment variable
- [ ] Set systemd resource limits (MemoryMax=400M, CPUQuota=50%)
- [ ] Configure automatic restart on failure (RestartSec=5s, exponential backoff)
- [ ] Add worker health check: `systemctl is-active uptrack-worker`
- [ ] Test profile builds: `nixos-rebuild build --flake '.#worker-test'`

### 1.4 Refactor Existing Node Configs

- [ ] Refactor `regions/europe/eu-a/default.nix` to use profiles (imports: base, infrastructure, worker)
- [ ] Refactor `regions/europe/eu-b/default.nix` to use profiles
- [ ] Refactor `regions/europe/eu-c/default.nix` to use profiles
- [ ] Refactor `regions/asia/india-hyderabad/worker-1/default.nix` to use profiles
- [ ] Refactor `regions/asia/india-hyderabad/worker-2/default.nix` to use profiles
- [ ] Verify each node builds identically: `nix-diff` old vs new builds

### 1.5 Validation

- [ ] Build all node configurations: `nixos-rebuild build --flake '.#eu-a'` (repeat for all 5 nodes)
- [ ] Verify build outputs are byte-identical to pre-refactor (except profile paths)
- [ ] Update flake.lock if needed
- [ ] Commit profile refactor: "refactor(nixos): introduce composable profiles for infrastructure and workers"

---

## Phase 2: Worker Application Configuration (1-2 days)

### 2.1 Oban Regional Queue Configuration

- [ ] Update `config/runtime.exs` to read `$WORKER_REGION` environment variable
- [ ] Map `WORKER_REGION` to Oban queue subscription:
  - `eu` → `[checks_eu: 10]`
  - `asia` → `[checks_asia: 10]`
  - `americas` → `[checks_americas: 10]`
- [ ] Add validation: fail fast if `WORKER_REGION` not set
- [ ] Add logging: "Worker configured for region: $WORKER_REGION, queues: $QUEUES"

### 2.2 Database Connection Configuration

- [ ] Configure Ecto to connect to PostgreSQL primary (100.64.1.1:5432)
- [ ] Set connection pool size: 10 connections (suitable for 512MB RAM)
- [ ] Configure connection timeouts: connect_timeout=10s, handshake_timeout=10s, timeout=30s
- [ ] Test connection from asia/india-s to eu/germany: `psql -h 100.64.1.1 -U uptrack`
- [ ] Verify Ecto handles reconnection on network blip

### 2.3 VictoriaMetrics Writer Configuration

- [ ] Configure worker to write results to VictoriaMetrics (100.64.1.2:8428)
- [ ] Use Finch HTTP client with connection pooling
- [ ] Add retry logic: 3 attempts with exponential backoff (1s, 2s, 4s)
- [ ] Add circuit breaker: fail fast after 10 consecutive failures
- [ ] Test write from india-s to austria VM: `curl -X POST http://100.64.1.2:8428/api/v1/write`

### 2.4 Worker Systemd Service

- [ ] Define `systemd.services.uptrack-worker` in `profiles/worker.nix`
- [ ] Set ExecStart to compiled Elixir release: `/nix/store/.../bin/uptrack_worker foreground`
- [ ] Set Type=notify (systemd waits for worker readiness notification)
- [ ] Add Environment variables: WORKER_REGION, DATABASE_URL, VICTORIAMETRICS_URL
- [ ] Configure Restart=on-failure, RestartSec=5s
- [ ] Test service start: `systemctl start uptrack-worker && journalctl -u uptrack-worker -f`

### 2.5 Resource Limits

- [ ] Set MemoryMax=400M in systemd service
- [ ] Set CPUQuota=50% in systemd service
- [ ] Test OOM behavior: trigger high memory usage, verify systemd kills and restarts worker
- [ ] Test CPU throttling: run CPU-intensive checks, verify worker doesn't exceed 50% CPU

---

## Phase 3: Regional Routing Implementation (1 day)

### 3.1 Monitor Region Field

- [ ] Add `regions` field to monitors table (array of strings)
- [ ] Create migration: `add_regions_to_monitors_table`
- [ ] Add `regions` field to Monitor schema (Ecto.Schema)
- [ ] Set default: `regions: ["eu"]` for existing monitors
- [ ] Add validation: `validate_length(:regions, min: 1)`

### 3.2 Scheduler Queue Routing

- [ ] Update `MonitorScheduler.schedule_check/1` to iterate over `monitor.regions`
- [ ] For each region, insert job to `checks_{region}` queue
- [ ] Log: "Scheduled check for monitor #{id} to regions: #{regions}"
- [ ] Test: create monitor with regions=["eu", "asia"], verify 2 jobs inserted

### 3.3 UI Region Selection

- [ ] Add multi-select dropdown to monitor form: "Check from regions"
- [ ] Options: EU (Europe), Asia (Asia-Pacific), Americas (North/South America)
- [ ] Add client-side validation: at least one region must be selected
- [ ] Add tooltip: "Checks will be performed from selected regions"
- [ ] Test: create monitor, select multiple regions, verify saved correctly

### 3.4 Queue Naming Convention

- [ ] Document queue naming: `checks_{region_code}` in `/docs/oban/regional-queues.md`
- [ ] Define region codes:
  - `eu` = Europe
  - `asia` = Asia-Pacific
  - `americas` = North + South America
  - `oceania` = Australia + New Zealand (future)
  - `africa` = Africa (future)
  - `middle_east` = Middle East (future)

---

## Phase 4: Deployment to Infrastructure Nodes (1 day)

### 4.1 Deploy to EU Nodes

- [ ] Deploy to eu-a: `nixos-rebuild switch --flake '.#eu-a' --target-host eu-a`
- [ ] Verify worker started: `ssh eu-a systemctl status uptrack-worker`
- [ ] Check logs: `ssh eu-a journalctl -u uptrack-worker -n 50`
- [ ] Verify queue subscription: logs should show "Subscribed to queues: [checks_eu: 10]"
- [ ] Repeat for eu-b and eu-c

### 4.2 Deploy to Asia Nodes

- [ ] Deploy to india-s: `nixos-rebuild switch --flake '.#india-s' --target-host india-s`
- [ ] Verify worker started: `ssh india-s systemctl status uptrack-worker`
- [ ] Check logs: `ssh india-s journalctl -u uptrack-worker -n 50`
- [ ] Verify queue subscription: logs should show "Subscribed to queues: [checks_asia: 10]"
- [ ] Repeat for india-w

### 4.3 Verify Inter-Regional Routing

- [ ] Create test monitor with regions: ["eu", "asia"]
- [ ] Wait for scheduler cycle (typically 1 minute)
- [ ] Query Oban: `SELECT queue, state FROM oban_jobs WHERE args->>'monitor_id' = <test_monitor_id>`
- [ ] Verify 2 jobs exist: one in `checks_eu`, one in `checks_asia`
- [ ] Watch logs: verify EU worker processes EU job, Asia worker processes Asia job
- [ ] Verify results written to VictoriaMetrics with correct region tag

---

## Phase 5: Monitoring & Observability (1 day)

### 5.1 Prometheus Metrics

- [ ] Add Prometheus metrics to worker application (use `:telemetry` + `:telemetry_metrics_prometheus`)
- [ ] Expose metrics endpoint at `:9568/metrics` (non-conflicting port)
- [ ] Define metrics:
  - `uptrack_worker_checks_total{region, status}` (counter)
  - `uptrack_worker_queue_depth{region}` (gauge)
  - `uptrack_worker_check_duration_seconds{region}` (histogram)
- [ ] Update Prometheus scrape config to include all 5 workers
- [ ] Test: `curl http://eu-a:9568/metrics | grep uptrack_worker`

### 5.2 Grafana Dashboard

- [ ] Create Grafana dashboard: "Regional Workers"
- [ ] Add panel: "Queue Depth by Region" (time series)
  - Query: `oban_queue_depth{queue=~"checks_.*"}`
- [ ] Add panel: "Checks Completed by Region" (rate)
  - Query: `rate(uptrack_worker_checks_total[5m])`
- [ ] Add panel: "Check Failure Rate" (gauge)
  - Query: `rate(uptrack_worker_checks_total{status="down"}[5m]) / rate(uptrack_worker_checks_total[5m])`
- [ ] Add panel: "Worker Memory Usage" (time series)
  - Query: `process_resident_memory_bytes{job="uptrack-worker"}`
- [ ] Save dashboard to `/infra/grafana/dashboards/regional-workers.json`

### 5.3 Alerting Rules

- [ ] Create Prometheus alert: `WorkerDown`
  - Condition: `up{job="uptrack-worker"} == 0 for 5m`
  - Severity: critical
- [ ] Create Prometheus alert: `HighRegionalQueueDepth`
  - Condition: `oban_queue_depth{queue=~"checks_.*"} > 10000 for 10m`
  - Severity: warning
- [ ] Create Prometheus alert: `LowRegionalCompletionRate`
  - Condition: `rate(uptrack_worker_checks_total{status="up"}[10m]) / rate(uptrack_worker_checks_total[10m]) < 0.95`
  - Severity: warning
- [ ] Add alerts to `/infra/prometheus/alerts/worker-alerts.yml`
- [ ] Reload Prometheus config: `curl -X POST http://prometheus:9090/-/reload`

### 5.4 Structured Logging

- [ ] Configure Logger to output JSON format (easier parsing)
- [ ] Add metadata to all check logs:
  - `worker_region`, `monitor_id`, `check_status`, `check_duration_ms`, `queue`
- [ ] Configure journald to index by `worker_region` field
- [ ] Test query: `journalctl WORKER_REGION=asia -n 100`

---

## Phase 6: Testing & Validation (1-2 days)

### 6.1 Unit Tests

- [ ] Test `MonitorScheduler.schedule_check/1` with multiple regions
- [ ] Test `ObanCheckWorker.perform/1` with various check types (HTTP, TCP, ping)
- [ ] Test worker configuration loading from `$WORKER_REGION`
- [ ] Test Oban queue routing (mock Oban.insert, verify correct queue)
- [ ] Run tests: `MIX_ENV=test mix test`

### 6.2 Integration Tests

- [ ] Test: Worker connects to PostgreSQL via Tailscale
  - Start worker, check logs for "Connected to PostgreSQL"
- [ ] Test: Worker pulls job from regional queue
  - Insert job to `checks_eu`, verify EU worker processes it
- [ ] Test: Worker writes result to VictoriaMetrics
  - Process check, query VM for result: `curl http://vm:8428/api/v1/query?query=uptrack_check_result`
- [ ] Test: Worker respects memory limit
  - Trigger high memory usage, verify systemd kills worker at 400MB
- [ ] Test: Worker restarts on failure
  - Kill worker process, verify systemd restarts it after 5s

### 6.3 Load Testing

- [ ] Create 100 test monitors with regions: ["eu", "asia"]
- [ ] Trigger scheduler to create 200 jobs (100 per region)
- [ ] Measure: time to complete all 200 jobs
  - Expected: <2 minutes (200 jobs / 60 total concurrency across 6 workers)
- [ ] Verify: no jobs failed, all results in VictoriaMetrics
- [ ] Verify: PostgreSQL connection pool didn't exhaust (max_connections=100)

### 6.4 Failure Scenarios

- [ ] Test: All Asia workers down, jobs queue
  - Stop india-s and india-w workers
  - Create monitor with regions: ["asia"]
  - Verify job queues in `checks_asia` (state="available")
  - Restart Asia workers, verify backlog processed
- [ ] Test: PostgreSQL primary failover
  - Stop PostgreSQL on eu-a (Patroni promotes eu-b)
  - Verify workers reconnect to new primary within 30s
  - Verify no jobs lost during failover
- [ ] Test: VictoriaMetrics down
  - Stop VictoriaMetrics on austria
  - Process checks, verify workers log errors but continue processing
  - Restart VictoriaMetrics, verify workers resume writing results

---

## Phase 7: Documentation (0.5 days)

### 7.1 Deployment Documentation

- [ ] Document worker deployment process in `/docs/deployment/workers.md`
- [ ] Document adding new worker node (step-by-step guide)
- [ ] Document troubleshooting common worker issues
- [ ] Add runbook: "Worker not processing jobs"
- [ ] Add runbook: "High regional queue depth"

### 7.2 Architecture Documentation

- [ ] Update `/docs/architecture/README.md` with worker architecture
- [ ] Document NixOS profile pattern in `/docs/deployment/nixos-profiles.md`
- [ ] Document regional queue routing in `/docs/oban/regional-queues.md`
- [ ] Create diagram: "Regional Worker Data Flow" (scheduler → queues → workers → VM)

### 7.3 Operations Documentation

- [ ] Document monitoring: "How to monitor regional workers"
- [ ] Document scaling: "How to add workers to existing region"
- [ ] Document region expansion: "How to add new region (Tokyo)"
- [ ] Document cost analysis: "Worker costs per region"

---

## Phase 8: Future Expansion Preparation (Optional)

### 8.1 Worker-Only Node Template

- [ ] Create template: `regions/_template/worker-only/default.nix`
- [ ] Document required customizations: hostname, NODE_REGION, SSH keys
- [ ] Test template: create `regions/asia/tokyo/default.nix` from template
- [ ] Document workflow: copy template → customize → deploy

### 8.2 Auto-Scaling Preparation (Future)

- [ ] Document manual scaling process: "Adding workers to handle load"
- [ ] Document metrics to watch: queue depth, completion rate, worker CPU/RAM
- [ ] Identify threshold: "Add worker when queue depth >5000 for 30 minutes"
- [ ] Note: Auto-scaling (Kubernetes HPA) deferred to 100K+ monitors scale

---

## Success Criteria

- [ ] ✅ All 5 workers running on infrastructure nodes (eu-a/b/c, india-s/w)
- [ ] ✅ Each worker processes only its region's queue
- [ ] ✅ Worker memory usage <300MB under load
- [ ] ✅ Adding Tokyo worker takes <30 minutes (new config + deploy)
- [ ] ✅ All checks complete within timeout (no queue backlog)
- [ ] ✅ Grafana dashboard shows per-region health
- [ ] ✅ Alerts fire correctly for worker failures and high queue depth
- [ ] ✅ Integration tests pass (100% success rate)
- [ ] ✅ Load test: 200 jobs complete in <2 minutes

---

## Estimated Timeline

| Phase | Duration | Parallel? |
|-------|----------|-----------|
| 1. NixOS Refactor | 2-3 days | No (foundational) |
| 2. Worker Config | 1-2 days | No (depends on Phase 1) |
| 3. Regional Routing | 1 day | Partially (can start while Phase 2 ongoing) |
| 4. Deployment | 1 day | No (depends on Phase 1-3) |
| 5. Monitoring | 1 day | Partially (can start with Phase 4) |
| 6. Testing | 1-2 days | No (validates everything) |
| 7. Documentation | 0.5 days | Partially (can document as you go) |

**Total**: 5-8 days (depends on parallelization and testing thoroughness)

---

## Dependencies

**Prerequisite changes**:
- `1-monitoring-infrastructure` (must be deployed first)

**Application code**:
- `lib/uptrack/monitoring/check_worker.ex` (already exists)
- `lib/uptrack/monitoring/oban_check_worker.ex` (already exists)
- `config/runtime.exs` (needs Oban queue config)

**Infrastructure**:
- PostgreSQL running on eu-a (100.64.1.1)
- VictoriaMetrics running on austria (100.64.1.2)
- Tailscale mesh network established
- All nodes can reach each other via Tailscale IPs

---

## Rollback Plan

**If deployment fails**:
1. Revert NixOS configs to previous generation: `nixos-rebuild switch --rollback`
2. Workers will stop, infrastructure services unaffected
3. Monitors continue to be scheduled (jobs queue until workers restored)
4. Fix issue, redeploy

**If worker causes issues**:
1. Stop worker: `systemctl stop uptrack-worker`
2. Infrastructure services continue normally
3. Debug worker in isolation
4. Restart when fixed: `systemctl start uptrack-worker`
