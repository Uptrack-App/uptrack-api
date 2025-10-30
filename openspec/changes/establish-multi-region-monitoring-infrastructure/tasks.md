# Implementation Tasks

## Phase 1: Foundation Setup (Week 1)

### Infrastructure Provisioning
- [ ] Document current node inventory (IPs, specs, access credentials)
- [ ] Setup Tailscale account and create tailnet
- [ ] Install Tailscale on all 5 nodes (eu-a, eu-b, eu-c, india-s, india-w)
- [ ] Assign static Tailscale IPs: 100.64.1.1-3 (EU), 100.64.1.10-11 (India)
- [ ] Verify connectivity between all nodes via Tailscale

### NixOS Base Configuration
- [ ] Create `infra/nixos/` directory structure
- [ ] Write `common.nix` with Tailscale and firewall config
- [ ] Create node-specific configs: `regions/eu/{eu-a,eu-b,eu-c}.nix`
- [ ] Create node-specific configs: `regions/india/{india-s,india-w}.nix`
- [ ] Setup `flake.nix` with all 5 node targets
- [ ] Test NixOS rebuild on one node (eu-a) to validate config

## Phase 2: etcd Cluster (Week 1-2)

### etcd Deployment
- [ ] Write `services/etcd.nix` module with cluster configuration
- [ ] Deploy etcd on eu-a, eu-b, eu-c (3-node cluster)
- [ ] Verify etcd cluster health: `etcdctl member list`
- [ ] Test etcd consensus: stop one node, verify cluster still functional
- [ ] Setup etcd monitoring (Prometheus metrics)

## Phase 3: PostgreSQL HA (Week 2)

### Patroni Setup
- [ ] Write `services/patroni.nix` module
- [ ] Configure PostgreSQL 17 with optimal settings (shared_buffers, work_mem)
- [ ] Deploy Patroni on eu-a (primary), eu-b (replica), eu-c (witness)
- [ ] Verify automatic failover: stop eu-a, confirm eu-b becomes primary
- [ ] Setup PostgreSQL async replica on india-s (read-only for Asian users)
- [ ] Configure connection pooling (PgBouncer if needed)

### Database Initialization
- [ ] Create app schema and users
- [ ] Create results schema for time-series data
- [ ] Apply security hardening (disable public schema, restrict permissions)
- [ ] Setup WAL archiving to india-w for backups

## Phase 4: VictoriaMetrics Cluster (Week 2-3)

### vmstorage Deployment
- [ ] Write `services/victoriametrics.nix` module
- [ ] Deploy vmstorage on eu-a, eu-b, eu-c (3 nodes)
- [ ] Configure 15-month retention: `-retentionPeriod=15M`
- [ ] Verify storage directories and permissions
- [ ] Test vmstorage health endpoints

### vminsert Deployment
- [ ] Deploy vminsert on eu-a, eu-c (2 nodes for redundancy)
- [ ] Configure vminsert with all 3 vmstorage endpoints
- [ ] Test metric ingestion via curl (sample data)
- [ ] Verify data distribution across vmstorage nodes

### vmselect Deployment
- [ ] Deploy vmselect on eu-b, eu-c, india-s (3 nodes)
- [ ] Configure vmselect with all 3 vmstorage endpoints
- [ ] Test queries via vmselect HTTP API
- [ ] Verify query performance (<100ms for typical dashboards)

### Load Balancing
- [ ] Setup Nginx/HAProxy for vminsert endpoints (if needed)
- [ ] Setup Nginx/HAProxy for vmselect endpoints (round-robin)
- [ ] Test failover: stop one vmselect, verify queries still work

## Phase 5: Monitoring Stack (Week 3)

### Prometheus Setup
- [ ] Write `services/prometheus.nix` module
- [ ] Deploy Prometheus on india-s
- [ ] Configure scrape targets for all nodes (node_exporter)
- [ ] Configure scrape targets for VictoriaMetrics components
- [ ] Configure scrape targets for PostgreSQL (postgres_exporter)
- [ ] Configure scrape targets for etcd

### Loki Setup
- [ ] Write `services/loki.nix` module
- [ ] Deploy Loki on india-w (lightweight log aggregation)
- [ ] Configure log shipping from all nodes (promtail)
- [ ] Verify log queries in Grafana

### Alertmanager Setup
- [ ] Write `services/alertmanager.nix` module
- [ ] Deploy Alertmanager on india-w
- [ ] Configure notification channels (email, Slack, PagerDuty)
- [ ] Setup basic alerts (node down, disk full, high CPU)

## Phase 6: Backups (Week 3)

### PostgreSQL Backups
- [ ] Write `services/backups.nix` module
- [ ] Configure daily pg_dump to india-w
- [ ] Configure continuous WAL archiving to india-w
- [ ] Test restore procedure (restore to test database)
- [ ] Document backup retention policy (30 days daily, 12 months monthly)

### VictoriaMetrics Backups
- [ ] Setup vmbackup cron job on all vmstorage nodes
- [ ] Configure backup destination (S3 or india-w local storage)
- [ ] Test vmrestore procedure
- [ ] Document backup schedule (weekly full, daily incremental)

## Phase 7: Documentation (Week 3-4)

### Architecture Documentation
- [ ] Create architecture diagram (nodes, services, data flows)
- [ ] Document Tailscale IP allocation
- [ ] Document service ports and endpoints
- [ ] Document firewall rules

### Operational Runbooks
- [ ] Write runbook: PostgreSQL manual failover
- [ ] Write runbook: Adding vmstorage node
- [ ] Write runbook: Provider migration procedure
- [ ] Write runbook: Disaster recovery
- [ ] Write runbook: Security incident response

### Developer Documentation
- [ ] Document how to deploy config changes
- [ ] Document how to access services for debugging
- [ ] Document how to query metrics and logs
- [ ] Document common troubleshooting scenarios

## Phase 8: Migration Preparation (Future)

### Pre-Migration Tasks
- [ ] Purchase 3 Netcup Austria nodes
- [ ] Add Netcup nodes to Tailscale (temp IPs 100.64.1.21-23)
- [ ] Deploy base NixOS config on Netcup nodes
- [ ] Verify connectivity from Netcup to existing cluster

### VictoriaMetrics Expansion
- [ ] Add 3 Netcup vmstorage nodes to cluster (expand to 6 total)
- [ ] Update vminsert/vmselect configs with new nodes
- [ ] Monitor data distribution (should rebalance automatically)
- [ ] Verify query performance remains good

### PostgreSQL Migration
- [ ] Setup Netcup node as PostgreSQL replica
- [ ] Let replication sync (monitor lag, should be <1 second)
- [ ] Schedule maintenance window (2-minute downtime)
- [ ] Promote Netcup replica to primary
- [ ] Update application connection strings
- [ ] Verify application functionality

### Cutover and Cleanup
- [ ] Remove Hostkey nodes from VictoriaMetrics cluster
- [ ] Reassign Tailscale IPs (Netcup nodes become 100.64.1.1-3)
- [ ] Update hostnames (Netcup nodes become eu-a, eu-b, eu-c)
- [ ] Update all configs to use new IPs
- [ ] Monitor for 1 week to ensure stability
- [ ] Cancel Hostkey subscriptions
- [ ] Archive Hostkey node data

## Validation

### Functional Tests
- [ ] Test: Write metrics to vminsert, read from vmselect
- [ ] Test: PostgreSQL failover (primary crashes, replica promoted)
- [ ] Test: etcd node failure (2/3 nodes maintain quorum)
- [ ] Test: Query metrics from India (should use india-s vmselect)
- [ ] Test: Backup restore (PostgreSQL and VictoriaMetrics)

### Performance Tests
- [ ] Benchmark: 666 samples/sec write throughput to VictoriaMetrics
- [ ] Benchmark: 222 inserts/sec to PostgreSQL
- [ ] Benchmark: Dashboard query latency (<100ms p95)
- [ ] Benchmark: PostgreSQL failover time (<30 seconds)

### Security Tests
- [ ] Verify: No public ports except SSH (22) and HTTPS (443)
- [ ] Verify: All inter-node traffic encrypted (Tailscale)
- [ ] Verify: PostgreSQL credentials not in plain text
- [ ] Verify: Firewall rules correct on all nodes

### Disaster Recovery Tests
- [ ] Test: Restore PostgreSQL from backup
- [ ] Test: Restore VictoriaMetrics from backup
- [ ] Test: Recover from complete EU cluster failure (using India replica)
- [ ] Test: Recover from single node failure

## Deployment Checklist

Before marking this change as complete:
- [ ] All tasks above completed
- [ ] All tests passing
- [ ] Documentation published
- [ ] Team trained on operations
- [ ] Monitoring dashboards created
- [ ] Alerts configured and tested
- [ ] Backup procedures validated
- [ ] Disaster recovery tested
