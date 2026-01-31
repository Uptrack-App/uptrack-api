# PostgreSQL Architecture

## Overview

Uptrack uses a dual-cluster PostgreSQL architecture with Patroni for high availability and Citus for horizontal scaling.

```
                    ┌─────────────────────────────────────────┐
                    │           Tailscale Network             │
                    └─────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        │                              │                              │
        ▼                              ▼                              ▼
┌───────────────┐             ┌───────────────┐             ┌───────────────┐
│  etcd Cluster │             │  Coordinator  │             │    Worker     │
│  (3 nodes)    │◄───DCS────► │    Cluster    │◄───Citus───►│    Cluster    │
│               │             │  nbg1 + nbg2  │             │  nbg3 + nbg4  │
└───────────────┘             └───────────────┘             └───────────────┘
                                     │
                                     ▼
                              ┌─────────────┐
                              │  PgBouncer  │
                              │  port 6432  │
                              └─────────────┘
                                     │
                                     ▼
                              ┌─────────────┐
                              │ Phoenix App │
                              └─────────────┘
```

## Cluster Topology

| Node | Role | Tailscale IP | Services |
|------|------|--------------|----------|
| nbg1 | Coordinator Primary/Standby | 100.64.1.1 | Patroni, etcd, PgBouncer, postgres_exporter |
| nbg2 | Coordinator Primary/Standby | 100.64.1.2 | Patroni, etcd, PgBouncer, postgres_exporter |
| nbg3 | Worker Primary/Standby | 100.64.1.3 | Patroni, etcd, postgres_exporter |
| nbg4 | Worker Primary/Standby | 100.64.1.4 | Patroni, postgres_exporter |

## Connection Details

### Application Connection (via PgBouncer)

```
Host: 100.64.1.1 (or 100.64.1.2)
Port: 6432
Database: uptrack
User: uptrack_app_user
Password: (from agenix secret)
Pool Mode: transaction
```

### Direct PostgreSQL Connection

```
Host: 100.64.1.1 (or current leader)
Port: 5432
Database: uptrack
User: uptrack_app_user
Socket: /run/patroni (on same host)
```

### Patroni REST API

```
http://100.64.1.1:8008/  - Cluster status
http://100.64.1.1:8008/leader  - Leader check
http://100.64.1.1:8008/replica  - Replica check
```

## Failover Procedures

### Automatic Failover

Patroni handles automatic failover when:
- Leader becomes unreachable
- Leader fails health checks
- Manual switchover is requested

No action required - standby is promoted automatically.

### Manual Switchover

Switch leadership to a specific node:

```bash
# SSH to any Patroni node
ssh root@100.64.1.1

# Check current cluster state
patronictl -c /etc/patroni-coordinator-nbg1.yaml list

# Switchover to nbg2
patronictl -c /etc/patroni-coordinator-nbg1.yaml switchover --leader nbg1 --candidate nbg2 --force

# Verify
patronictl -c /etc/patroni-coordinator-nbg1.yaml list
```

### Restart a Node

```bash
# Restart PostgreSQL on a specific node
patronictl -c /etc/patroni-coordinator-nbg1.yaml restart coordinator nbg1

# Restart entire cluster (rolling)
patronictl -c /etc/patroni-coordinator-nbg1.yaml restart coordinator
```

## Monitoring

### Metrics Endpoints

| Node | Endpoint | Metrics |
|------|----------|---------|
| nbg1-4 | :9187/metrics | PostgreSQL, Citus, replication |
| nbg1-4 | :8008/metrics | Patroni cluster health |

### Key Metrics

- `pg_stat_replication_lag_seconds` - Replication lag
- `pg_database_connections` - Connection count per database
- `citus_worker_nodes_is_active` - Citus worker health
- `pg_up` - PostgreSQL availability

### Check Cluster Health

```bash
# Check Patroni cluster
patronictl -c /etc/patroni-coordinator-nbg1.yaml list

# Check etcd cluster
etcdctl --endpoints=100.64.1.1:2379 endpoint health --cluster

# Check Citus workers
psql -h /run/patroni -U postgres -d uptrack -c "SELECT * FROM citus_get_active_worker_nodes();"

# Check replication lag
psql -h /run/patroni -U postgres -c "SELECT client_addr, state, sent_lsn, write_lsn, replay_lag FROM pg_stat_replication;"
```

## Scaling Procedures

### Add a New Worker Node

1. Deploy Patroni on new node with `worker` scope
2. Wait for synchronization
3. Register with Citus coordinator:

```sql
SELECT citus_add_node('new-worker-ip', 5432);
```

### Rebalance Shards

```sql
-- Check shard distribution
SELECT nodename, count(*) FROM citus_shards GROUP BY nodename;

-- Rebalance (moves shards evenly)
SELECT citus_rebalance_start();

-- Check progress
SELECT * FROM citus_rebalance_status();
```

## Database Schema

### Multi-tenancy

All tenant tables have `organization_id` for data isolation:

```
organizations (tenant root)
├── users (belongs_to organization)
├── monitors (belongs_to organization, user)
├── alert_channels (belongs_to organization, user)
├── status_pages (belongs_to organization, user)
└── incidents (belongs_to organization, monitor)
```

### Tables

| Table | Type | Distribution |
|-------|------|--------------|
| organizations | Tenant root | Local (future: distributed by id) |
| users | Tenant | Local (future: by organization_id) |
| monitors | Tenant | Local (future: by organization_id) |
| incidents | Tenant | Local (future: by organization_id) |
| monitor_checks | High volume | Local |
| regions | Reference | Local (future: reference table) |

## Troubleshooting

### Node Won't Start

```bash
# Check Patroni logs
journalctl -u patroni -n 100

# Check PostgreSQL logs
journalctl -u patroni -n 100 | grep -i error

# Check etcd connectivity
etcdctl --endpoints=100.64.1.1:2379 endpoint health
```

### Replication Lag

```bash
# Check lag on standby
psql -h /run/patroni -U postgres -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();"

# Force sync (on leader)
SELECT pg_switch_wal();
```

### Citus Worker Unreachable

```bash
# Check worker status
psql -d uptrack -c "SELECT * FROM pg_dist_node;"

# Remove failed worker
SELECT citus_remove_node('failed-worker-ip', 5432);

# Re-add after recovery
SELECT citus_add_node('worker-ip', 5432);
```

### PgBouncer Issues

```bash
# Check PgBouncer status
systemctl status pgbouncer

# Check pool stats
psql -h 127.0.0.1 -p 6432 -U pgbouncer -d pgbouncer -c "SHOW POOLS;"

# Reload config
systemctl reload pgbouncer
```

## Configuration Files

| File | Description |
|------|-------------|
| `/etc/patroni-coordinator-*.yaml` | Patroni cluster config |
| `/etc/pgbouncer/pgbouncer.ini` | PgBouncer config |
| `/run/pgbouncer/userlist.txt` | PgBouncer user auth |
| `/run/patroni/` | PostgreSQL socket directory |

## Secrets

Managed via agenix:

| Secret | Purpose |
|--------|---------|
| `postgres-password.age` | PostgreSQL superuser |
| `replicator-password.age` | Replication user |
| `uptrack-app-password.age` | Application user |
