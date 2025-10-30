# Capability: monitoring/regional-routing

Intelligent routing of monitoring checks to appropriate regional workers based on user-selected regions.

## ADDED Requirements

### Requirement: Regional Queue Management
The system SHALL define regional queues (checks_eu, checks_asia, checks_americas), the scheduler SHALL insert jobs to all queues matching monitor.regions, and unprocessed jobs SHALL remain in queue when regional workers are offline.

**ID:** regional-routing-001
**Priority:** Critical

Regional queues enable geographic distribution without complex routing logic. Oban provides persistence and retries.

#### Scenario: Scheduler routes to multiple regions
**Given** monitor "example.com" has regions: ["eu", "asia"]
**When** scheduler creates check jobs
**Then** scheduler inserts job to checks_eu queue
**And** scheduler inserts job to checks_asia queue
**And** both jobs have same monitor_id but different queue assignments

#### Scenario: Jobs persist when workers offline
**Given** all Asia workers (india-s, india-w) are stopped
**When** scheduler inserts jobs to checks_asia queue
**Then** jobs remain in PostgreSQL oban_jobs table
**And** jobs state = "available" (not "executing")
**And** when Asia workers restart, they process backlog (FIFO order)

#### Scenario: EU workers ignore Asia queue
**Given** eu-a worker subscribes to checks_eu queue only
**When** jobs exist in checks_asia queue
**Then** eu-a worker does not fetch checks_asia jobs
**And** Asia jobs wait for Asia workers (no cross-region processing)

---

### Requirement: Monitor Region Configuration
Monitors SHALL have a regions field (multi-select: eu, asia, americas, oceania, africa, middle_east), the UI SHALL validate at least one region is selected, and changing monitor regions SHALL take effect on next scheduled check cycle.

**ID:** regional-routing-002
**Priority:** Critical

Users control which regions check their monitors. Multi-region checks detect region-specific outages.

#### Scenario: User selects multiple regions
**Given** user creates monitor "api.example.com"
**When** user selects regions: ["eu", "asia", "americas"]
**Then** monitor.regions = ["eu", "asia", "americas"]
**And** on next check cycle, scheduler creates 3 jobs (one per region)

#### Scenario: UI validates region selection
**Given** user creates monitor
**When** user deselects all regions
**Then** UI shows error: "At least one region must be selected"
**And** save button is disabled

#### Scenario: Region change affects next cycle
**Given** monitor has regions: ["eu"]
**When** user changes to regions: ["eu", "asia"]
**Then** next check cycle creates 2 jobs (eu + asia)
**And** previous in-flight EU-only jobs complete normally

---

### Requirement: Regional Check Distribution
When multiple workers subscribe to same regional queue, Oban SHALL distribute jobs using PostgreSQL SKIP LOCKED, workers SHALL NOT process duplicate jobs, and job distribution SHALL balance load across available workers.

**ID:** regional-routing-003
**Priority:** High

SKIP LOCKED ensures each job is processed exactly once. Multiple workers increase throughput without coordination.

#### Scenario: Three EU workers share checks_eu queue
**Given** eu-a, eu-b, eu-c all subscribe to checks_eu with concurrency 10
**When** scheduler inserts 300 jobs to checks_eu
**Then** each worker fetches ~100 jobs (distributed via SKIP LOCKED)
**And** no job is processed by multiple workers
**And** all 300 jobs complete within 2 minutes (300 / 30 total concurrency)

#### Scenario: Worker failure doesn't lose jobs
**Given** eu-a fetches job and starts processing
**When** eu-a crashes before completing job
**Then** job remains in "executing" state for 5 minutes (Oban timeout)
**And** after timeout, job state returns to "available"
**And** another worker (eu-b or eu-c) processes the job

#### Scenario: Single worker in region processes all jobs
**Given** only india-s subscribes to checks_asia (india-w is down)
**When** scheduler inserts 100 jobs to checks_asia
**Then** india-s processes all 100 jobs sequentially
**And** no jobs are skipped or dropped

---

### Requirement: Regional Failure Handling
When all workers in a region are down, jobs SHALL queue up to 10,000 before alerting, Oban SHALL retry failed jobs 3 times with exponential backoff, and cross-region fallback SHALL NOT occur (jobs stay in regional queue).

**ID:** regional-routing-004
**Priority:** High

Regional isolation prevents cascading failures. Jobs wait for regional recovery rather than contaminating other regions' results.

#### Scenario: All Asia workers down, jobs queue
**Given** india-s and india-w workers are stopped
**When** scheduler inserts 1000 jobs to checks_asia over 1 hour
**Then** all 1000 jobs remain in checks_asia queue (state="available")
**And** no alert fires (queue depth <10,000)
**And** when Asia workers restart, they process 1000-job backlog

#### Scenario: Alert fires when queue exceeds threshold
**Given** all Asia workers down for 8 hours
**When** checks_asia queue depth reaches 10,000 jobs
**Then** Alertmanager fires alert: "HighRegionalQueueDepth"
**And** alert includes: region=asia, queue_depth=10000, duration=8h

#### Scenario: Failed jobs retry in same region
**Given** Asia worker processes job and gets HTTP timeout
**When** worker marks job as failed (attempt 1/3)
**Then** Oban schedules retry in 1 minute (exponential backoff)
**And** retry job stays in checks_asia queue (same region)
**And** after 3 failed attempts, job moves to "discarded" state

---

### Requirement: Regional Performance Monitoring
The system SHALL track per-region check completion rate, SHALL alert if completion rate drops below 95%, and SHALL expose per-region metrics in Grafana dashboard showing queue depth, completion rate, and average check duration.

**ID:** regional-routing-005
**Priority:** Medium

Regional metrics enable detecting and diagnosing region-specific issues.

#### Scenario: Prometheus scrapes per-region metrics
**Given** workers expose Prometheus metrics
**When** Prometheus scrapes all workers
**Then** metrics include:
  - oban_jobs_completed_total{queue="checks_eu"}
  - oban_jobs_failed_total{queue="checks_asia"}
  - oban_queue_depth{queue="checks_americas"}

#### Scenario: Alert on low regional completion rate
**Given** EU workers process checks_eu queue
**When** completion rate drops to 80% for 10 minutes
**Then** Alertmanager fires alert: "LowRegionalCompletionRate"
**And** alert includes: region=eu, rate=80%, threshold=95%

#### Scenario: Grafana dashboard shows regional health
**Given** Grafana is deployed
**When** operator opens "Regional Monitoring" dashboard
**Then** dashboard shows per-region panels:
  - Queue depth (time series, last 6 hours)
  - Completion rate (gauge, current value)
  - Average check duration (time series)
  - Failed checks (counter, last 24 hours)
