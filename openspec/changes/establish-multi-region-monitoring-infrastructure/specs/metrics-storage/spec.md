# Capability: infrastructure/metrics-storage

VictoriaMetrics cluster for time-series metrics storage with 15-month retention.

## ADDED Requirements

### Requirement: VictoriaMetrics Cluster Architecture
The system SHALL deploy VictoriaMetrics in cluster mode with 3 vmstorage, 2 vminsert, and 3 vmselect nodes, with all vmstorage nodes retaining metrics for 15 months using -retentionPeriod=15M.

**ID:** infra-metrics-001
**Priority:** Critical

Cluster mode provides horizontal scalability and redundancy for 10,000 monitors generating 666 samples/sec. 15-month retention is a business requirement.

#### Scenario: Deploy initial 3-vmstorage cluster
**Given** 3 EU nodes are provisioned
**When** deploying VictoriaMetrics components
**Then** vmstorage runs on eu-a, eu-b, eu-c (ports 8400, 8401, 8482)
**And** vminsert runs on eu-a, eu-c (port 8480)
**And** vmselect runs on eu-b, eu-c, india-s (port 8481)
**And** metrics are distributed across all 3 vmstorage nodes

#### Scenario: Verify retention configuration
**Given** vmstorage is deployed
**When** checking the process flags
**Then** each vmstorage instance has -retentionPeriod=15M configured via NixOS
**And** metrics older than 15 months are deleted automatically

---

### Requirement: Performance and Capacity
The cluster SHALL sustain 666 samples/sec ingestion rate, dashboard queries SHALL complete in <100ms (p95), and the cluster SHALL allocate ~35GB total storage with 3x headroom.

**ID:** infra-metrics-002
**Priority:** High

Core workload requirements for current user base and responsive user experience.

#### Scenario: Sustained write throughput
**Given** application writes 666 samples/sec via vminsert
**When** monitoring ingestion rate over 1 hour
**Then** all samples are accepted without drops
**And** vminsert queue depth remains <1000
**And** vmstorage write latency p99 <50ms

#### Scenario: Fast dashboard query
**Given** a dashboard queries last 1 hour of data for 10 monitors
**When** issuing the query to vmselect
**Then** query completes in <50ms (p95)

#### Scenario: Monitor storage usage
**Given** the cluster stores 15 months of data
**When** checking disk usage on vmstorage nodes
**Then** each node uses ~12GB (35GB ÷ 3)
**And** disk usage is <30% (leaving 70% headroom)

---

### Requirement: Horizontal Scaling and Geographic Distribution
The system SHALL support adding vmstorage nodes without downtime or data loss, and SHALL deploy vmselect on india-s to serve Asian users.

**ID:** infra-metrics-003
**Priority:** Medium

Growth to 30K, 50K, 100K monitors requires adding storage capacity. Asian users get better query performance with local vmselect.

#### Scenario: Add 4th vmstorage node
**Given** a cluster with 3 vmstorage nodes
**When** adding a 4th vmstorage node and updating vminsert/vmselect configs
**Then** new writes are distributed across 4 nodes
**And** existing data remains on original 3 nodes
**And** no metrics are lost during the process

#### Scenario: Route Asian users to india-s vmselect
**Given** application detects user is in Asia
**When** user loads a dashboard
**Then** queries are sent to india-s vmselect (100.64.1.10:8481)
**And** query completes in ~200ms (vs ~350ms if querying EU vmselect)

---

### Requirement: Operations and Reliability
The system SHALL expose Prometheus metrics for all VictoriaMetrics components, SHALL support backing up vmstorage data using vmbackup to Backblaze B2, and SHALL tolerate single vmstorage node failure with graceful degradation.

**ID:** infra-metrics-004
**Priority:** Medium

Observability, disaster recovery, and high availability without complex replication.

#### Scenario: Scrape vmstorage metrics
**Given** Prometheus runs on india-s
**When** scraping metrics from vmstorage (port 8482)
**Then** metrics include vm_rows, vm_free_disk_space_bytes, vm_slow_queries_total
**And** alerts fire if vm_free_disk_space_bytes <20GB

#### Scenario: Backup vmstorage to B2
**Given** vmstorage on eu-a has 15 months of data
**When** running vmbackup to b2://uptrack/vm/
**Then** backup completes in <30 minutes
**And** backup is incremental

#### Scenario: Query with one vmstorage down
**Given** vmstorage on eu-b is down
**When** querying metrics via vmselect
**Then** vmselect queries only eu-a and eu-c vmstorage
**And** query returns partial data (2/3 of metrics)
**And** UI shows warning "Some data unavailable"
