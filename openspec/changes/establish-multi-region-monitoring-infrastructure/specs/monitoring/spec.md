# Capability: infrastructure/monitoring

Observability stack for infrastructure health monitoring.

## ADDED Requirements

### Requirement: Metrics Collection Infrastructure
The system SHALL deploy Prometheus on india-s to scrape metrics from all infrastructure components, all 5 nodes SHALL run node_exporter, and all PostgreSQL nodes SHALL run postgres_exporter.

**ID:** infra-monitor-001
**Priority:** Critical

Centralized monitoring enables visibility into system health. Node_exporter provides foundation metrics, postgres_exporter monitors database health.

#### Scenario: Prometheus scrapes all nodes
**Given** Prometheus runs on india-s
**When** Prometheus scrape cycle runs (every 15 seconds)
**Then** Prometheus successfully scrapes node_exporter, postgres_exporter, etcd, and VictoriaMetrics on all nodes
**And** scrape success rate >99%

#### Scenario: Node exporter provides system metrics
**Given** node_exporter runs on eu-a
**When** Prometheus scrapes http://100.64.1.1:9100/metrics
**Then** metrics include CPU, memory, disk, and network stats

#### Scenario: postgres_exporter tracks replication lag
**Given** postgres_exporter runs on eu-b (replica)
**When** Prometheus scrapes metrics
**Then** pg_replication_lag_seconds shows current lag

---

### Requirement: Logging and Alerting Infrastructure
The system SHALL deploy Loki on india-w to aggregate logs from all nodes, and SHALL deploy Alertmanager on india-w to route alerts via multiple channels.

**ID:** infra-monitor-002
**Priority:** High

Centralized logs enable troubleshooting. Alertmanager ensures alerts reach on-call engineers reliably.

#### Scenario: Promtail ships logs to Loki
**Given** Promtail runs on all 5 nodes
**When** services write logs to systemd journal
**Then** Promtail sends logs to Loki on india-w:3100
**And** logs are retained for 30 days

#### Scenario: Send critical alert via multiple channels
**Given** Alertmanager is configured with email and Slack
**When** a critical alert fires
**Then** Alertmanager sends notification to email and Slack with alert details

---

### Requirement: Alert Rules for Critical and Warning Conditions
The system SHALL define alerting rules for critical infrastructure failures (node down, disk >90%, etcd quorum lost) and warning alerts for degraded performance (CPU >80% for 30 min, memory >85%, replication lag >10s).

**ID:** infra-monitor-003
**Priority:** Critical

Critical issues trigger immediate response. Warnings enable proactive intervention before failures.

#### Scenario: Node down alert
**Given** eu-b stops responding to Prometheus scrapes
**When** node is down for >5 minutes
**Then** alert "NodeDown" fires with severity=critical

#### Scenario: High CPU warning
**Given** eu-a CPU usage exceeds 80% for 30 minutes
**When** Prometheus evaluates CPU metrics
**Then** alert "HighCPU" fires with severity=warning

---

### Requirement: Monitoring Operations and Self-Monitoring
The system SHALL provide Grafana dashboards showing resource usage trends, the monitoring stack itself SHALL be monitored for failures, and Prometheus/Loki SHALL use resource-efficient retention policies.

**ID:** infra-monitor-004
**Priority:** Medium

Proactive scaling requires visibility into growth trends. If monitoring breaks, no one knows infrastructure is failing. India-w has limited capacity.

#### Scenario: Infrastructure overview dashboard
**Given** Grafana is deployed
**When** operator opens "Infrastructure Overview" dashboard
**Then** dashboard shows CPU, memory, disk usage per node with 7-day trend

#### Scenario: Alert on Prometheus scrape failures
**Given** Prometheus scrapes 25 targets
**When** scrape failure rate exceeds 10% for 5 minutes
**Then** alert "PrometheusScrapeFailing" fires

#### Scenario: Prometheus retention
**Given** Prometheus stores metrics locally on india-s
**When** metrics older than 15 days accumulate
**Then** Prometheus deletes metrics older than 15 days
**And** Prometheus disk usage stays <10GB
