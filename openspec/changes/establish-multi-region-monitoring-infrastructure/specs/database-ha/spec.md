# Capability: infrastructure/database-ha

PostgreSQL high availability with Patroni and etcd for automatic failover.

## ADDED Requirements

### Requirement: Distributed Consensus with etcd
The system SHALL deploy a 3-node etcd cluster in EU for distributed consensus, and India nodes SHALL NOT participate in the etcd cluster due to 150ms latency.

**ID:** infra-dbha-001
**Priority:** Critical

etcd provides distributed locking needed for Patroni automatic failover. 150ms latency causes split-brain risk.

#### Scenario: Deploy etcd on 3 EU nodes
**Given** eu-a, eu-b, eu-c are provisioned
**When** deploying etcd as a 3-node cluster
**Then** each node runs etcd listening on ports 2379 (client) and 2380 (peer)
**And** cluster achieves quorum (2/3 nodes required)
**And** etcdctl member list shows 3 healthy members

#### Scenario: etcd survives single node failure
**Given** etcd cluster with 3 nodes
**When** eu-c stops responding
**Then** eu-a and eu-b maintain quorum (2/3)
**And** etcd continues accepting writes

---

### Requirement: PostgreSQL High Availability with Patroni
The system SHALL deploy PostgreSQL 17 with optimized configuration for 8GB RAM nodes, and SHALL use Patroni to automatically promote a replica within 30 seconds of primary failure.

**ID:** infra-dbha-002
**Priority:** Critical

PostgreSQL 17 offers 2x better write throughput. Manual failover takes 5-60 minutes; automatic failover reduces downtime 90%+.

#### Scenario: PostgreSQL configured for 8GB RAM
**Given** PostgreSQL 17 is deployed on eu-a
**When** checking configuration
**Then** shared_buffers = 2GB, effective_cache_size = 6GB, work_mem = 16MB, maintenance_work_mem = 512MB

#### Scenario: Automatic failover on primary failure
**Given** eu-a is PostgreSQL primary, eu-b is sync replica
**When** eu-a crashes
**Then** within 30 seconds, application reconnects to new primary
**And** no data loss occurs (synchronous replication)

---

### Requirement: Replication Architecture
PostgreSQL primary SHALL use synchronous replication to at least one EU replica for zero data loss, india-s SHALL run an asynchronous replica for read queries, and EU-c SHALL run as a Patroni witness node.

**ID:** infra-dbha-003
**Priority:** High

Sync replication ensures zero data loss in EU. 150ms latency prevents synchronous replication to India. Witness enables 2/3 quorum without full replication.

#### Scenario: Zero data loss on failover
**Given** application commits transaction T1 successfully
**When** primary eu-a crashes immediately after commit
**Then** transaction T1 is present in eu-b (synchronous replica)
**And** no committed transactions are lost

#### Scenario: India replica serves Asian read queries
**Given** india-s is ~1-2 seconds behind primary
**When** an Asian user queries monitor status
**Then** application sends SELECT to india-s
**And** user receives data that may be 1-2 seconds stale (acceptable)

---

### Requirement: Operational Safety
The system SHALL monitor replication lag and alert if lag exceeds 10 seconds, SHALL prevent split-brain scenarios, and documentation SHALL include manual failover procedures.

**ID:** infra-dbha-004
**Priority:** High

High replication lag indicates problems. Split-brain causes data corruption. Manual procedures provide backup plan.

#### Scenario: Monitor replication lag
**Given** eu-b replicates from eu-a
**When** Prometheus scrapes postgres_exporter metrics
**Then** pg_replication_lag_seconds shows <1 second normally
**And** alert fires if lag >10 seconds for 2 minutes

#### Scenario: Network partition handling
**Given** network partition separates eu-a from eu-b/eu-c
**When** Patroni detects partition
**Then** eu-a (minority side, 1/3) demotes itself
**And** only one primary exists at any time
