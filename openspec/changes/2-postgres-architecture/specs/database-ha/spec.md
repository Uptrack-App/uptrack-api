## ADDED Requirements

### Requirement: Citus Distributed Cluster

The system SHALL deploy PostgreSQL with Citus extension as a distributed cluster consisting of one coordinator and two worker nodes.

**Details:**
- Coordinator (nbg-1): Routes queries, stores metadata, hosts local tables (Oban)
- Worker 1 (nbg-2): Stores shards 1,3,5... of distributed tables
- Worker 2 (nbg-3): Stores shards 2,4,6... of distributed tables
- All nodes communicate over Tailscale VPN (100.64.1.x)

#### Scenario: Cluster initialization
- **GIVEN** three NixOS nodes with PostgreSQL 17 and Citus extension
- **WHEN** the coordinator registers workers via `citus_add_node()`
- **THEN** the cluster reports 2 active worker nodes
- **AND** distributed queries execute across all workers

#### Scenario: Distributed query routing
- **GIVEN** a query with `organization_id` in WHERE clause
- **WHEN** the query is executed on the coordinator
- **THEN** the coordinator routes to the single shard containing that organization
- **AND** query latency is <10ms for simple lookups

#### Scenario: Fan-out query
- **GIVEN** a query without `organization_id` filter
- **WHEN** the query is executed on the coordinator
- **THEN** the coordinator fans out to all workers
- **AND** results are merged and returned to the client

---

### Requirement: Organization-Based Sharding

The system SHALL distribute all tenant data by `organization_id` to enable horizontal scaling and data isolation.

**Details:**
- All tenant tables include `organization_id` column
- Tables are co-located by `organization_id` for efficient JOINs
- Reference tables (regions, plans) are replicated to all workers
- Oban tables remain local on coordinator

#### Scenario: Tenant data isolation
- **GIVEN** two organizations with IDs org-A and org-B
- **WHEN** org-A's data is on worker-1 and org-B's data is on worker-2
- **THEN** queries for org-A never access worker-2
- **AND** queries for org-B never access worker-1

#### Scenario: Co-located JOIN
- **GIVEN** monitors and incidents tables co-located by `organization_id`
- **WHEN** joining monitors and incidents for a single organization
- **THEN** the JOIN executes on a single worker (no network shuffle)
- **AND** query performance matches single-node PostgreSQL

#### Scenario: Reference table access
- **GIVEN** regions table marked as reference table
- **WHEN** joining monitors with regions
- **THEN** the JOIN executes locally on each worker
- **AND** no cross-node data transfer occurs

---

### Requirement: Oban Local Tables

The system SHALL keep Oban job queue tables local on the coordinator node, not distributed across workers.

**Details:**
- Oban tables (oban_jobs, oban_peers, oban_producers) in `oban` schema
- Oban requires PostgreSQL LISTEN/NOTIFY (doesn't work across shards)
- Job processing happens on application nodes connected to coordinator

#### Scenario: Oban job insertion
- **GIVEN** Oban configured with `prefix: "oban"`
- **WHEN** application inserts a job via `Oban.insert()`
- **THEN** the job is stored in coordinator's local `oban.oban_jobs` table
- **AND** NOTIFY triggers Oban workers to pick up the job

#### Scenario: Oban isolation from Citus
- **GIVEN** Citus distribution commands have been run
- **WHEN** querying `oban.oban_jobs`
- **THEN** the query executes only on coordinator
- **AND** `citus_tables` does not list Oban tables

---

### Requirement: pgBackRest Backup to Backblaze B2

The system SHALL backup all PostgreSQL nodes using pgBackRest to Backblaze B2 with encryption and point-in-time recovery capability.

**Details:**
- Each node has independent pgBackRest stanza
- Backups stored in S3-compatible Backblaze B2
- AES-256-CBC encryption for all backup data
- Weekly full backups, daily differential backups
- Continuous WAL archiving for PITR

#### Scenario: Automated daily backup
- **GIVEN** pgBackRest configured with B2 credentials
- **WHEN** the daily backup timer triggers at 02:00
- **THEN** a differential backup completes successfully
- **AND** backup metadata is updated in B2

#### Scenario: Continuous WAL archiving
- **GIVEN** PostgreSQL configured with `archive_mode = on`
- **WHEN** a WAL segment is completed
- **THEN** pgBackRest pushes the segment to B2
- **AND** the segment is encrypted before upload

#### Scenario: Single node restore
- **GIVEN** worker-1 has failed and needs restoration
- **WHEN** administrator runs `pgbackrest --stanza=worker1 restore`
- **THEN** the latest backup is downloaded from B2
- **AND** WAL segments are replayed to reach consistent state
- **AND** worker-1 rejoins the Citus cluster

#### Scenario: Point-in-time recovery
- **GIVEN** data corruption discovered at 15:00
- **WHEN** administrator restores all nodes to 14:00 timestamp
- **THEN** all nodes restore to the same point-in-time
- **AND** cluster state is consistent across coordinator and workers
- **AND** data after 14:00 is not present

---

### Requirement: Coordinator High Availability

The system SHALL provide automatic failover for the Citus coordinator using Patroni and etcd.

**Details:**
- Patroni manages coordinator primary/standby
- etcd cluster (3 nodes) provides consensus
- Failover completes in <30 seconds
- Application reconnects automatically via Patroni endpoint

#### Scenario: Coordinator failure detection
- **GIVEN** Patroni monitoring coordinator health
- **WHEN** coordinator primary becomes unresponsive for 30 seconds
- **THEN** Patroni initiates leader election via etcd
- **AND** standby coordinator is promoted to primary

#### Scenario: Automatic failover
- **GIVEN** coordinator primary fails
- **WHEN** Patroni promotes standby to primary
- **THEN** workers reconnect to new coordinator within 30 seconds
- **AND** application queries resume without manual intervention

#### Scenario: Split-brain prevention
- **GIVEN** network partition between coordinator nodes
- **WHEN** both nodes attempt to become primary
- **THEN** etcd quorum (2/3 nodes) determines single leader
- **AND** fenced node cannot accept writes

---

### Requirement: NixOS Declarative Configuration

The system SHALL deploy all PostgreSQL, Citus, Patroni, and pgBackRest components using NixOS modules.

**Details:**
- All configuration in `/infra/nixos/modules/services/`
- Secrets managed via sops-nix or agenix
- Reproducible deployments via `nixos-rebuild`
- Rollback capability via NixOS generations

#### Scenario: Deploy new node
- **GIVEN** NixOS configuration for a new worker node
- **WHEN** running `nixos-rebuild switch --flake '.#nbg-4'`
- **THEN** PostgreSQL, Citus worker, and pgBackRest are installed
- **AND** configuration matches the declarative specification

#### Scenario: Configuration rollback
- **GIVEN** a failed deployment causing PostgreSQL issues
- **WHEN** running `nixos-rebuild switch --rollback`
- **THEN** the previous NixOS generation is activated
- **AND** PostgreSQL returns to previous working configuration

#### Scenario: Secret management
- **GIVEN** PostgreSQL passwords stored in sops-encrypted files
- **WHEN** NixOS activates the configuration
- **THEN** secrets are decrypted and placed in `/run/secrets/`
- **AND** PostgreSQL reads passwords from secret files
- **AND** secrets are not visible in Nix store

---

### Requirement: Multi-Tenant Schema Design

The system SHALL implement a multi-tenant schema with organizations as the top-level entity and organization_id as the distribution key.

**Details:**
- `organizations` table is the distribution anchor
- All tenant tables have `organization_id` foreign key
- Single database with schema-based isolation
- Organization slug for URL-friendly identification

#### Scenario: Organization creation
- **GIVEN** a new user signs up
- **WHEN** the system creates their account
- **THEN** an organization is created with unique slug
- **AND** the user is associated with the organization
- **AND** organization_id is set on all user's resources

#### Scenario: Data isolation query
- **GIVEN** user belongs to organization "acme"
- **WHEN** user queries their monitors
- **THEN** only monitors with organization_id matching "acme" are returned
- **AND** query includes organization_id in WHERE clause

#### Scenario: Cross-organization prevention
- **GIVEN** user in organization "acme" attempts to access "beta" data
- **WHEN** the query is executed
- **THEN** no results are returned
- **AND** access is denied at the database level via organization_id filter
