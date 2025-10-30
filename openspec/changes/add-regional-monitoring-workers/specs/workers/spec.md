# Capability: application/workers

Distributed Oban workers that perform monitoring checks from multiple geographic regions.

## ADDED Requirements

### Requirement: Regional Worker Application Deployment
The system SHALL deploy Uptrack worker application on all nodes (eu-a, eu-b, eu-c, india-s, india-w) as a systemd service, each worker SHALL connect to PostgreSQL primary (Germany) via Tailscale, and each worker SHALL use <300MB RAM.

**ID:** worker-app-001
**Priority:** Critical

Workers enable regional monitoring. Co-locating on infrastructure nodes is zero-cost and validates architecture before scaling.

#### Scenario: Worker systemd service starts on eu-a
**Given** eu-a node has NixOS configuration deployed
**When** systemd starts the uptrack-worker service
**Then** the service status shows "active (running)"
**And** worker process uses <300MB RAM
**And** worker logs show "Connected to PostgreSQL at 100.64.1.1:5432"

#### Scenario: Worker connects to PostgreSQL via Tailscale
**Given** PostgreSQL primary runs on eu-a (100.64.1.1)
**When** worker on india-s starts
**Then** worker connects to postgresql://100.64.1.1:5432/uptrack via Tailscale tunnel
**And** connection latency is ~150ms (EU-India baseline)

#### Scenario: Worker consumes <300MB RAM
**Given** worker application is running on india-s
**When** worker processes 10 concurrent checks
**Then** RSS memory usage remains <300MB
**And** node has >200MB free RAM for other services

---

### Requirement: Oban Queue-Based Regional Routing
Each worker SHALL subscribe to only its region's Oban queue, workers SHALL use Oban concurrency of 10 per queue, and workers SHALL acknowledge completed jobs in batches to reduce database round trips.

**ID:** worker-app-002
**Priority:** Critical

Queue-based routing enables geographic distribution. Oban provides retries, observability, and job persistence for free.

#### Scenario: EU worker processes only EU queue
**Given** worker on eu-a is configured with queues: [checks_eu: 10]
**When** scheduler inserts jobs to checks_eu and checks_asia queues
**Then** eu-a worker pulls jobs from checks_eu only
**And** checks_asia jobs remain in queue (processed by Asia workers)

#### Scenario: Asia worker processes only Asia queue
**Given** worker on india-s is configured with queues: [checks_asia: 10]
**When** scheduler inserts job to checks_asia queue
**Then** india-s worker pulls and processes the job
**And** job is completed within region-appropriate timeout (15s for Asia)

#### Scenario: Multiple workers share regional queue load
**Given** eu-a, eu-b, eu-c all subscribe to checks_eu queue
**When** scheduler inserts 300 jobs to checks_eu
**Then** jobs are distributed across 3 workers (Oban SKIP LOCKED)
**And** all jobs complete within 2 minutes (300 jobs / 30 total concurrency)

---

### Requirement: Monitoring Check Execution
Workers SHALL use existing CheckWorker module to perform HTTP, TCP, ping, and keyword checks, workers SHALL enforce 30-second timeout per check, and workers SHALL write results to VictoriaMetrics (Austria) via Tailscale.

**ID:** worker-app-003
**Priority:** Critical

CheckWorker already exists in codebase. Workers reuse this battle-tested code for consistent check behavior.

#### Scenario: Worker performs HTTP check
**Given** Oban job contains monitor_id for HTTP monitor
**When** worker processes the job
**Then** CheckWorker performs HTTP GET to monitor.url
**And** result includes status_code, response_time, response_headers
**And** result is written to VictoriaMetrics within 1 second

#### Scenario: Worker enforces check timeout
**Given** monitor has timeout=30s
**When** worker performs check on unresponsive host
**Then** check fails after 30 seconds (not longer)
**And** worker creates check record with status="down" and error_message="timeout"

#### Scenario: Worker handles check failures gracefully
**Given** worker performs check on monitor with invalid URL
**When** check raises exception
**Then** worker catches exception and creates check record with status="down"
**And** Oban retries the job (max_attempts: 3)
**And** worker continues processing other jobs (failure doesn't crash worker)

---

### Requirement: Resource Limits and Isolation
Worker systemd services SHALL have MemoryMax=400M to prevent OOM, workers SHALL have CPUQuota=50% to prevent CPU starvation, and workers SHALL restart automatically on failure with exponential backoff.

**ID:** worker-app-004
**Priority:** High

Resource limits prevent workers from impacting infrastructure services. Automatic restart ensures high availability.

#### Scenario: Worker respects memory limit
**Given** worker systemd service has MemoryMax=400M
**When** worker memory usage exceeds 400MB
**Then** systemd kills the worker process
**And** systemd restarts worker after 5 seconds
**And** alert fires: "WorkerOOMKilled"

#### Scenario: Worker respects CPU quota
**Given** worker systemd service has CPUQuota=50%
**When** worker performs 10 concurrent CPU-intensive checks
**Then** worker uses at most 50% of 1 CPU core
**And** PostgreSQL and VictoriaMetrics on same node remain responsive

#### Scenario: Worker restarts on failure
**Given** worker process crashes (exit code 1)
**When** systemd detects process exit
**Then** systemd restarts worker after 5 seconds
**And** restart delay doubles on repeated failures (5s, 10s, 20s, 40s)
**And** worker reconnects to PostgreSQL and resumes processing queue

---

### Requirement: Worker Monitoring and Observability
Workers SHALL expose Prometheus metrics at :9568/metrics, workers SHALL log to systemd journal with structured metadata, and Grafana SHALL display per-region queue depth and check completion rate.

**ID:** worker-app-005
**Priority:** Medium

Observability enables troubleshooting worker issues and detecting regional problems.

#### Scenario: Worker exposes Prometheus metrics
**Given** worker application is running on eu-a
**When** Prometheus scrapes http://eu-a:9568/metrics
**Then** metrics include:
  - uptrack_worker_checks_total{region="eu", status="up|down"}
  - uptrack_worker_queue_depth{region="eu"}
  - uptrack_worker_check_duration_seconds{region="eu"}

#### Scenario: Worker logs structured to journal
**Given** worker performs check on monitor "example.com"
**When** check completes
**Then** journalctl shows structured log:
  - WORKER_REGION=eu
  - MONITOR_ID=123
  - CHECK_STATUS=up
  - CHECK_DURATION_MS=245

#### Scenario: Grafana dashboard shows regional health
**Given** Grafana is deployed
**When** operator opens "Regional Workers" dashboard
**Then** dashboard shows per-region:
  - Queue depth (last 1 hour trend)
  - Checks completed (rate per minute)
  - Failure rate (percentage)
  - Worker resource usage (CPU, RAM)
