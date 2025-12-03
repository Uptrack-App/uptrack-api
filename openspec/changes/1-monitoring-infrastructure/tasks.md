# Implementation Tasks

## Phase 1: Foundation (Netcup + Oracle Nodes)

### 1.1 Tailscale Network Setup
- [ ] Create Tailscale account and tailnet
- [ ] Install Tailscale on nbg-1, nbg-2, nbg-3 (Netcup)
- [ ] Install Tailscale on india-strong, india-weak (Oracle)
- [ ] Assign static Tailscale IPs:
  - [ ] 100.64.1.1 → nbg-1
  - [ ] 100.64.1.2 → nbg-2
  - [ ] 100.64.1.3 → nbg-3
  - [ ] 100.64.3.1 → india-strong
  - [ ] 100.64.3.2 → india-weak
- [ ] Verify connectivity: ping all nodes via Tailscale IPs
- [ ] Configure Tailscale ACLs for layer segregation

### 1.2 NixOS Base Configuration
- [ ] Create `infra/nixos/common/base.nix` with Tailscale + firewall
- [ ] Create node configs: `regions/europe/nuremberg/{nbg-1,nbg-2,nbg-3}/default.nix`
- [ ] Create node configs: `regions/asia/india/{india-strong,india-weak}/default.nix`
- [ ] Setup `flake.nix` with all 5 node targets
- [ ] Test NixOS rebuild on nbg-1 to validate config

### 1.3 etcd Cluster (Nuremberg Only)
- [ ] Write `modules/services/etcd.nix` module
- [ ] Deploy etcd on nbg-1, nbg-2, nbg-3
- [ ] Configure cluster with Tailscale IPs (100.64.1.1-3)
- [ ] Verify cluster health: `etcdctl member list`
- [ ] Test consensus: stop one node, verify 2/3 quorum works

## Phase 2: PostgreSQL HA (Patroni)

### 2.1 Patroni Setup
- [ ] Write `modules/services/patroni.nix` module
- [ ] Configure PostgreSQL 17 settings (shared_buffers, work_mem)
- [ ] Deploy Patroni on nbg-1 (primary)
- [ ] Deploy Patroni on nbg-2 (sync replica)
- [ ] Deploy Patroni on nbg-3 (async replica/witness)
- [ ] Configure synchronous_standby_names for nbg-2
- [ ] Verify Patroni cluster: `patronictl list`

### 2.2 Failover Testing
- [ ] Test automatic failover: stop nbg-1, verify nbg-2 promotes
- [ ] Measure failover time (target: <30 seconds)
- [ ] Test manual failover: `patronictl switchover`
- [ ] Verify zero data loss with sync replica

### 2.3 India DR Replica
- [ ] Setup PostgreSQL on india-strong (async replica)
- [ ] Configure streaming replication from Patroni primary
- [ ] Verify replication lag monitoring
- [ ] Document manual promotion procedure

### 2.4 Database Initialization
- [ ] Create app schema and users
- [ ] Create results schema for time-series data
- [ ] Apply security hardening (disable public schema)
- [ ] Setup WAL archiving to india-weak (Backblaze B2)

## Phase 3: Storage Layer (Hybrid: nbg-3 + HostHatch)

### 3.1 HostHatch Provisioning
- [ ] Purchase 1 HostHatch Storage VPS (Amsterdam region)
  - [ ] storage-1: 1TB+ NVMe, 2 vCPU, 2GB RAM (~€6/mo)
- [ ] Install NixOS or configure base OS
- [ ] Install Tailscale on storage-1
- [ ] Assign static Tailscale IP:
  - [ ] 100.64.2.1 → storage-1
- [ ] Verify connectivity to Netcup nodes (<10ms latency)

### 3.2 vmstorage Deployment (Hybrid HA)
- [ ] Write `modules/services/vmstorage.nix` module
- [ ] Deploy vmstorage on nbg-3 (colocated with PostgreSQL async replica)
- [ ] Deploy vmstorage on storage-1 (dedicated storage)
- [ ] Configure retention: `-retentionPeriod=15M`
- [ ] Configure storage paths:
  - [ ] nbg-3: `/var/lib/vmstorage` (512GB shared with PG)
  - [ ] storage-1: `/var/lib/vmstorage` (1TB dedicated)
- [ ] Configure ports:
  - [ ] 8400 (vminsert connections)
  - [ ] 8401 (vmselect connections)
  - [ ] 8482 (HTTP API)
- [ ] Verify storage health endpoints on both nodes
- [ ] Setup disk usage monitoring for nbg-3 (alert at 80%)

## Phase 4: Compute Layer (VictoriaMetrics)

### 4.1 vminsert Deployment
- [ ] Write `modules/services/vminsert.nix` module
- [ ] Deploy vminsert on nbg-1, nbg-2
- [ ] Configure with both vmstorage endpoints and replicationFactor=2:
  ```
  -replicationFactor=2
  -storageNode=100.64.1.3:8400  # nbg-3
  -storageNode=100.64.2.1:8400  # storage-1
  ```
- [ ] Configure port 8480 (HTTP API)
- [ ] Test metric ingestion via curl
- [ ] Verify data appears on both vmstorage nodes

### 4.2 vmselect Deployment
- [ ] Write `modules/services/vmselect.nix` module
- [ ] Deploy vmselect on nbg-1, nbg-2, nbg-3
- [ ] Deploy vmselect on india-strong
- [ ] Configure with both vmstorage endpoints:
  ```
  -storageNode=100.64.1.3:8401  # nbg-3
  -storageNode=100.64.2.1:8401  # storage-1
  ```
- [ ] Configure port 8481 (HTTP API)
- [ ] Test queries via vmselect HTTP API
- [ ] Verify deduplication works (same data from both nodes)

### 4.3 Integration Testing
- [ ] Write sample metrics to vminsert (nbg-1)
- [ ] Query metrics from vmselect (nbg-2)
- [ ] Query metrics from vmselect (india-strong)
- [ ] Verify data replication: same data on nbg-3 and storage-1
- [ ] Test HA: stop one vmstorage, verify queries still work
- [ ] Benchmark: 666 samples/sec ingestion
- [ ] Benchmark: <100ms query latency (EU), <200ms (Asia)

## Phase 5: Monitoring Stack

### 5.1 Prometheus Setup
- [ ] Write `modules/services/prometheus.nix` module
- [ ] Deploy Prometheus on india-strong
- [ ] Configure scrape targets:
  - [ ] node_exporter on all 8 nodes
  - [ ] VictoriaMetrics components (vminsert, vmselect, vmstorage)
  - [ ] PostgreSQL (postgres_exporter)
  - [ ] etcd metrics
  - [ ] Patroni metrics
- [ ] Configure remote_write to VictoriaMetrics (optional)

### 5.2 Loki Setup
- [ ] Write `modules/services/loki.nix` module
- [ ] Deploy Loki on india-weak
- [ ] Configure log retention
- [ ] Deploy promtail on all nodes
- [ ] Verify log queries

### 5.3 Alertmanager Setup
- [ ] Write `modules/services/alertmanager.nix` module
- [ ] Deploy Alertmanager on india-weak
- [ ] Configure notification channels (email, Slack)
- [ ] Setup critical alerts:
  - [ ] Node down >5 minutes
  - [ ] PostgreSQL primary down
  - [ ] etcd quorum lost
  - [ ] Disk >90% full
  - [ ] vmstorage unreachable

## Phase 6: Backups

### 6.1 PostgreSQL Backups
- [ ] Write `modules/services/pg-backup.nix` module
- [ ] Configure WAL-G for daily base backups to B2
- [ ] Configure continuous WAL archiving to B2
- [ ] Test restore procedure (PITR)
- [ ] Document backup retention: 30 days

### 6.2 VictoriaMetrics Backups
- [ ] Setup vmbackup daily cron on all vmstorage nodes
- [ ] Configure backup destination (B2 or india-weak)
- [ ] Test vmrestore procedure
- [ ] Document backup schedule: daily incremental

## Phase 7: Documentation

### 7.1 Architecture Documentation
- [ ] Create architecture diagram (Mermaid or draw.io)
- [ ] Document Tailscale IP allocation
- [ ] Document service ports and endpoints
- [ ] Document firewall rules

### 7.2 Operational Runbooks
- [ ] Runbook: PostgreSQL manual failover
- [ ] Runbook: Adding vmstorage node
- [ ] Runbook: Disaster recovery (EU failure)
- [ ] Runbook: Security incident response

### 7.3 Developer Documentation
- [ ] Document deployment workflow
- [ ] Document service access for debugging
- [ ] Document metric/log queries
- [ ] Document common troubleshooting

## Validation Checklist

### Functional Tests
- [ ] Write metrics → vminsert → vmstorage → vmselect → read
- [ ] Verify replicationFactor=2: data on both nbg-3 and storage-1
- [ ] PostgreSQL failover (primary crashes, replica promoted)
- [ ] etcd node failure (2/3 quorum)
- [ ] Query from India vmselect
- [ ] Backup/restore PostgreSQL
- [ ] Backup/restore VictoriaMetrics

### Performance Tests
- [ ] 666 samples/sec write throughput
- [ ] 222 inserts/sec PostgreSQL
- [ ] <100ms query latency (EU)
- [ ] <200ms query latency (Asia)
- [ ] <30 second PostgreSQL failover

### Security Tests
- [ ] No public ports except 22, 443
- [ ] All inter-node traffic via Tailscale
- [ ] PostgreSQL credentials encrypted
- [ ] Firewall rules verified

### Disaster Recovery Tests
- [ ] Restore PostgreSQL from B2
- [ ] Restore VictoriaMetrics from backup
- [ ] Recover from single node failure
- [ ] vmstorage HA: stop nbg-3, verify queries still work via storage-1
- [ ] vmstorage HA: stop storage-1, verify queries still work via nbg-3

### Capacity Tests (nbg-3 Shared Storage)
- [ ] Monitor nbg-3 disk usage: vmstorage + PostgreSQL < 80%
- [ ] Verify alert triggers at 80% disk usage
- [ ] Document expansion plan if nbg-3 reaches 70%

## Deployment Checklist

Before marking complete:
- [ ] All tasks above completed
- [ ] All tests passing
- [ ] Documentation published
- [ ] Monitoring dashboards created
- [ ] Alerts configured and tested
- [ ] Backup procedures validated
- [ ] DR tested at least once
