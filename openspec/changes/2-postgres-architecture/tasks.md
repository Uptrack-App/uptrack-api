# Implementation Tasks: PostgreSQL Architecture

**Change ID**: `2-postgres-architecture`
**Prerequisites**: `1-monitoring-infrastructure` (Tailscale networking)

---

## Phase 1: NixOS Module Development

### 1.1 PostgreSQL + Citus Module

- [ ] Create `/infra/nixos/modules/services/postgresql-citus.nix`
- [ ] Configure PostgreSQL 17 with Citus extension
- [ ] Set `shared_preload_libraries = 'citus'`
- [ ] Configure authentication (pg_hba.conf) for Tailscale IPs
- [ ] Add resource limits (shared_buffers, work_mem based on 8GB RAM)
- [ ] Test module builds: `nix build .#nixosConfigurations.nbg-1.config.system.build.toplevel`

### 1.2 pgBackRest Module

- [ ] Create `/infra/nixos/modules/services/pgbackrest.nix`
- [ ] Configure S3-compatible endpoint for Backblaze B2
- [ ] Add stanza configuration per node (coordinator, worker1, worker2)
- [ ] Configure archive_command for continuous WAL archiving
- [ ] Add systemd timers for full (weekly) and diff (daily) backups
- [ ] Configure encryption (aes-256-cbc)
- [ ] Test module builds

### 1.3 Patroni Module (Coordinator HA)

- [ ] Create `/infra/nixos/modules/services/patroni.nix`
- [ ] Configure etcd connection (100.64.1.1-3:2379)
- [ ] Set Patroni scope and name
- [ ] Configure PostgreSQL parameters via Patroni
- [ ] Add health check endpoint (:8008)
- [ ] Test module builds

### 1.4 Secrets Management

- [ ] Set up sops-nix or agenix for secret management
- [ ] Create secrets for:
  - [ ] PostgreSQL superuser password
  - [ ] Replication user password
  - [ ] Citus inter-node password
  - [ ] pgBackRest encryption key
  - [ ] B2 application key ID and key
- [ ] Test secrets decryption on target nodes

---

## Phase 2: Schema Migration

### 2.1 Organizations Table

- [ ] Create migration: `add_organizations_table`
- [ ] Add `organizations` table with UUID primary key
- [ ] Add fields: name, slug (unique), plan, settings
- [ ] Add timestamps
- [ ] Test migration locally

### 2.2 Add organization_id to Existing Tables

- [ ] Create migration: `add_organization_id_to_all_tables`
- [ ] Add `organization_id` column to:
  - [ ] users
  - [ ] monitors
  - [ ] incidents
  - [ ] incident_updates
  - [ ] alert_channels
  - [ ] status_pages
  - [ ] status_page_monitors
  - [ ] monitor_checks (if still in PG, not VictoriaMetrics)
- [ ] Create foreign key constraints
- [ ] Test migration locally

### 2.3 Data Backfill

- [ ] Create migration: `backfill_organization_id`
- [ ] Create default organization for existing users
- [ ] Backfill organization_id for all users
- [ ] Backfill organization_id for all dependent tables
- [ ] Make organization_id NOT NULL after backfill
- [ ] Test with production data copy

### 2.4 Citus Distribution (Separate Migration)

- [ ] Create migration: `distribute_tables_citus`
- [ ] Wrap in conditional (only run on Citus cluster)
- [ ] `create_distributed_table('organizations', 'id')`
- [ ] `create_distributed_table` for all tenant tables with `colocate_with`
- [ ] `create_reference_table` for regions, plans
- [ ] Verify Oban tables remain local
- [ ] Test on Citus dev cluster

---

## Phase 3: Application Code Updates

### 3.1 Organization Context

- [ ] Create `lib/uptrack/organizations.ex` context module
- [ ] Add `Organization` schema
- [ ] Add `get_organization!/1`, `get_organization_by_slug!/1`
- [ ] Add `create_organization/1`, `update_organization/2`
- [ ] Add `list_organizations/0` (admin only)

### 3.2 Update Existing Schemas

- [ ] Add `organization_id` field to all schemas:
  - [ ] User
  - [ ] Monitor
  - [ ] Incident
  - [ ] IncidentUpdate
  - [ ] AlertChannel
  - [ ] StatusPage
- [ ] Update changesets to require organization_id
- [ ] Add `belongs_to :organization` associations

### 3.3 Update Queries

- [ ] Audit all Repo queries for missing organization_id
- [ ] Update `Accounts` context to include organization_id
- [ ] Update `Monitoring` context to include organization_id
- [ ] Update `Incidents` context to include organization_id
- [ ] Update `StatusPages` context to include organization_id
- [ ] Add organization scoping to all list functions

### 3.4 Update LiveView/Controllers

- [ ] Add organization to session/assigns
- [ ] Update all LiveViews to pass organization to contexts
- [ ] Add organization switcher (if multi-org per user)
- [ ] Test all user flows with organization scoping

---

## Phase 4: Backblaze B2 Setup

### 4.1 B2 Bucket Configuration

- [ ] Create B2 bucket: `uptrack-pgbackrest`
- [ ] Enable server-side encryption
- [ ] Create application key with bucket-specific access
- [ ] Set lifecycle rules (optional: archive old backups to cheaper storage)
- [ ] Document bucket configuration

### 4.2 Test B2 Connectivity

- [ ] Test S3-compatible API access from local machine
- [ ] Verify endpoint: `s3.us-west-004.backblazeb2.com`
- [ ] Test upload/download with AWS CLI
- [ ] Document B2 access credentials location

---

## Phase 5: Coordinator Deployment (nbg-1)

### 5.1 Deploy PostgreSQL + Citus

- [ ] Update `infra/nixos/regions/europe/nbg-1/default.nix`
- [ ] Import postgresql-citus module
- [ ] Configure as Citus coordinator
- [ ] Set Tailscale IP: 100.64.1.1
- [ ] Deploy: `nixos-rebuild switch --flake '.#nbg-1' --target-host nbg-1`
- [ ] Verify PostgreSQL running: `systemctl status postgresql`
- [ ] Verify Citus extension: `psql -c "SELECT citus_version()"`

### 5.2 Deploy pgBackRest

- [ ] Import pgbackrest module
- [ ] Configure stanza: `coordinator`
- [ ] Deploy configuration
- [ ] Initialize stanza: `pgbackrest --stanza=coordinator stanza-create`
- [ ] Run initial full backup: `pgbackrest --stanza=coordinator backup --type=full`
- [ ] Verify backup in B2 console

### 5.3 Create Database and Users

- [ ] Create uptrack database
- [ ] Create application user (uptrack_app)
- [ ] Create replication user (replicator)
- [ ] Create Citus user for inter-node communication
- [ ] Grant appropriate permissions
- [ ] Test application connection

---

## Phase 6: Worker Deployment (nbg-2, nbg-3)

### 6.1 Deploy Worker 1 (nbg-2)

- [ ] Update `infra/nixos/regions/europe/nbg-2/default.nix`
- [ ] Configure as Citus worker
- [ ] Set Tailscale IP: 100.64.1.2
- [ ] Deploy: `nixos-rebuild switch --flake '.#nbg-2' --target-host nbg-2`
- [ ] Verify PostgreSQL running
- [ ] Configure pgBackRest stanza: `worker1`
- [ ] Initialize and run backup

### 6.2 Deploy Worker 2 (nbg-3)

- [ ] Update `infra/nixos/regions/europe/nbg-3/default.nix`
- [ ] Configure as Citus worker
- [ ] Set Tailscale IP: 100.64.1.3
- [ ] Deploy: `nixos-rebuild switch --flake '.#nbg-3' --target-host nbg-3`
- [ ] Verify PostgreSQL running
- [ ] Configure pgBackRest stanza: `worker2`
- [ ] Initialize and run backup

### 6.3 Register Workers with Coordinator

- [ ] On coordinator, add worker nodes:
  ```sql
  SELECT citus_add_node('100.64.1.2', 5432);
  SELECT citus_add_node('100.64.1.3', 5432);
  ```
- [ ] Verify cluster: `SELECT * FROM citus_get_active_worker_nodes();`
- [ ] Test distributed query: `SELECT run_command_on_workers('SELECT 1');`

---

## Phase 7: Schema Deployment

### 7.1 Run Migrations

- [ ] Run organizations migration on coordinator
- [ ] Run organization_id migration on coordinator
- [ ] Run backfill migration on coordinator
- [ ] Run Citus distribution migration
- [ ] Verify shards created: `SELECT * FROM citus_shards;`
- [ ] Verify data distribution: `SELECT * FROM citus_tables;`

### 7.2 Verify Distribution

- [ ] Insert test organization
- [ ] Insert test user with organization_id
- [ ] Insert test monitor with organization_id
- [ ] Query with organization_id (should route to single shard)
- [ ] Query without organization_id (should fan out - verify slower)
- [ ] Verify Oban tables local: `SELECT * FROM oban.oban_jobs;`

---

## Phase 8: Backup Verification

### 8.1 Test Single Node Restore

- [ ] Create test database on worker1
- [ ] Insert test data
- [ ] Run backup
- [ ] Destroy test database
- [ ] Restore from backup
- [ ] Verify data intact

### 8.2 Test Coordinated PITR

- [ ] Note current timestamp
- [ ] Insert test data across all nodes
- [ ] Run `restore-cluster.sh` to previous timestamp
- [ ] Verify test data NOT present (restored to before insert)
- [ ] Verify cluster health: `SELECT * FROM citus_check_cluster_node_health();`

### 8.3 Document Restore Procedures

- [ ] Create `/docs/infrastructure/pgbackrest-restore.md`
- [ ] Document single-node restore
- [ ] Document coordinated cluster restore
- [ ] Document PITR procedure
- [ ] Add runbook for common failure scenarios

---

## Phase 9: Monitoring Setup

### 9.1 Prometheus Metrics

- [ ] Deploy postgres_exporter on each node
- [ ] Add Citus-specific queries
- [ ] Configure Prometheus scrape targets
- [ ] Verify metrics in Prometheus

### 9.2 Grafana Dashboard

- [ ] Create PostgreSQL + Citus dashboard
- [ ] Add panels:
  - [ ] Cluster health
  - [ ] Shard distribution
  - [ ] Query latency by type
  - [ ] Connection counts
  - [ ] Replication lag (when applicable)
  - [ ] Backup status
- [ ] Save dashboard to `/infra/grafana/dashboards/`

### 9.3 Alerting

- [ ] Create alert: `PostgreSQLDown`
- [ ] Create alert: `CituSWorkerUnreachable`
- [ ] Create alert: `BackupFailed`
- [ ] Create alert: `BackupStale` (no backup in 25 hours)
- [ ] Create alert: `HighReplicationLag`
- [ ] Add alerts to Alertmanager

---

## Phase 10: Documentation

### 10.1 Operations Documentation

- [ ] Create `/docs/infrastructure/postgresql-citus.md`
- [ ] Document architecture overview
- [ ] Document common operations (add worker, rebalance shards)
- [ ] Document troubleshooting guide
- [ ] Document scaling procedures

### 10.2 Development Documentation

- [ ] Create `/docs/development/citus-queries.md`
- [ ] Document query patterns (include organization_id)
- [ ] Document co-location requirements
- [ ] Document reference table usage
- [ ] Add examples for common operations

### 10.3 Update Existing Docs

- [ ] Update `/docs/architecture/README.md` with Citus info
- [ ] Update `/CLAUDE.md` with Citus deployment notes
- [ ] Link to new documentation

---

## Success Criteria

- [ ] Citus cluster running (1 coordinator + 2 workers)
- [ ] All tenant tables distributed by `organization_id`
- [ ] Oban tables remain local and functional
- [ ] pgBackRest backing up all 3 nodes to B2
- [ ] PITR restore tested successfully
- [ ] All existing functionality works with organization scoping
- [ ] Prometheus metrics and Grafana dashboard deployed
- [ ] Documentation complete

---

## Rollback Plan

### If Citus Causes Issues

1. Migrations are reversible (undistribute tables)
2. Can fall back to standard PostgreSQL
3. Keep coordinator as single-node PostgreSQL
4. organization_id columns remain (good for future)

### If pgBackRest Fails

1. Fall back to pg_dump for immediate backup
2. Debug pgBackRest configuration
3. WAL archiving continues independently

### If Worker Fails

1. Cluster continues with degraded capacity
2. Restore worker from pgBackRest
3. Re-register with coordinator
4. Citus rebalances automatically

---

## Estimated Timeline

| Phase | Tasks | Parallel? |
|-------|-------|-----------|
| 1. NixOS Modules | 4 tasks | No (foundational) |
| 2. Schema Migration | 4 tasks | No (sequential) |
| 3. Application Code | 4 tasks | Partially |
| 4. B2 Setup | 2 tasks | Yes (with Phase 1-3) |
| 5. Coordinator Deploy | 3 tasks | No |
| 6. Worker Deploy | 3 tasks | Partially (workers parallel) |
| 7. Schema Deploy | 2 tasks | No |
| 8. Backup Verification | 3 tasks | No |
| 9. Monitoring | 3 tasks | Yes (with Phase 8) |
| 10. Documentation | 3 tasks | Yes (ongoing) |
