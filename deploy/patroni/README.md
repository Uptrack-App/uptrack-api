# Patroni Configuration

Patroni manages Postgres high availability with automatic failover.

## Files

- `patroni-node-a.yml` - Configuration for Node A (primary candidate)
- `patroni-node-b.yml` - Configuration for Node B (replica)

## Prerequisites

1. **etcd cluster running** on all 3 nodes (A, B, C)
2. **Postgres 16 installed** on Node A & B
3. **TimescaleDB extension installed**
4. **Tailscale IPs configured** (100.A.A.A, 100.B.B.B, 100.C.C.C)

## Installation Steps

### 1. Install Patroni (Nodes A & B)

```bash
# Ubuntu/Debian
apt install patroni postgresql-16 postgresql-contrib-16

# Or via pip
pip3 install patroni[etcd3]
```

### 2. Configure Tailscale IPs

Edit both YAML files and replace placeholder IPs:
- `100.A.A.A` → Node A's actual Tailscale IP
- `100.B.B.B` → Node B's actual Tailscale IP
- `100.C.C.C` → Node C's actual Tailscale IP

Find your Tailscale IPs:
```bash
tailscale ip -4
```

### 3. Set Strong Passwords

Edit both YAML files and change:
- `CHANGE_ME_POSTGRES_PASSWORD` → Strong superuser password
- `CHANGE_ME_REPLICATOR_PASSWORD` → Strong replication password
- `CHANGE_ME_UPTRACK_PASSWORD` → Strong app user password

Generate passwords:
```bash
openssl rand -base64 32
```

### 4. Deploy Configs

```bash
# Node A
scp patroni-node-a.yml node-a:/etc/patroni/patroni.yml
ssh node-a "chown postgres:postgres /etc/patroni/patroni.yml && chmod 600 /etc/patroni/patroni.yml"

# Node B
scp patroni-node-b.yml node-b:/etc/patroni/patroni.yml
ssh node-b "chown postgres:postgres /etc/patroni/patroni.yml && chmod 600 /etc/patroni/patroni.yml"
```

### 5. Start Patroni

```bash
# Node A
ssh node-a "systemctl enable --now patroni"

# Node B (wait 30s after A starts)
ssh node-b "systemctl enable --now patroni"
```

### 6. Verify Cluster

```bash
# Check cluster status (from any node)
patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster

# Expected output:
# + Cluster: uptrack-pg-cluster ----+---------+---------+----+-----------+
# | Member | Host        | Role    | State   | TL | Lag in MB |
# +--------+-------------+---------+---------+----+-----------+
# | node-a | 100.A.A.A   | Leader  | running |  1 |           |
# | node-b | 100.B.B.B   | Replica | running |  1 |         0 |
# +--------+-------------+---------+---------+----+-----------+

# Check REST API (should return leader info)
curl http://127.0.0.1:8008 | jq .
```

## Key Configuration Details

### TTL and Loop Settings

- `ttl: 30` - How long leader lease lasts (seconds)
- `loop_wait: 10` - How often Patroni checks state (seconds)
- `retry_timeout: 10` - Timeout for retries (seconds)

**Failover time:** ~30 seconds (1 TTL period)

### Replication Slots

- `use_slots: true` - Physical replication slots (prevents WAL deletion while replica is down)
- `max_replication_slots: 10` - Allow up to 10 slots

### pg_rewind

- `use_pg_rewind: true` - Allows rejoining after split-brain without full re-sync

### Connection Pooling

Each node can handle:
- `max_connections: 100` total connections
- App uses ~10-20 connections per node (via pool_size)
- Leaves room for monitoring, admin, replication

## REST API Endpoints

Patroni exposes a REST API on port 8008:

```bash
# Check if node is primary
curl http://127.0.0.1:8008/primary

# Check if node is replica
curl http://127.0.0.1:8008/replica

# Health check (any role)
curl http://127.0.0.1:8008/health

# Cluster info
curl http://127.0.0.1:8008/patroni | jq .
```

Use these for HAProxy health checks!

## Common Operations

### Manual Failover

```bash
# Switch primary from node-a to node-b
patronictl -c /etc/patroni/patroni.yml switchover uptrack-pg-cluster --master node-a --candidate node-b
```

### Restart Postgres (Patroni-aware)

```bash
# Graceful restart (waits for connections to close)
patronictl -c /etc/patroni/patroni.yml restart uptrack-pg-cluster node-a

# Reload config without restart
patronictl -c /etc/patroni/patroni.yml reload uptrack-pg-cluster node-a
```

### Reinitialize Node (from scratch)

```bash
# Useful if node is out of sync
patronictl -c /etc/patroni/patroni.yml reinit uptrack-pg-cluster node-b
```

### Maintenance Mode

```bash
# Pause automatic failover (for maintenance)
patronictl -c /etc/patroni/patroni.yml pause uptrack-pg-cluster

# Resume automatic failover
patronictl -c /etc/patroni/patroni.yml resume uptrack-pg-cluster
```

## Troubleshooting

### Patroni won't start

```bash
# Check logs
journalctl -u patroni -f

# Common issues:
# 1. etcd not reachable
etcdctl endpoint health --cluster

# 2. Postgres already running (stop it first)
systemctl stop postgresql

# 3. Data directory not empty
rm -rf /var/lib/postgresql/16/main
```

### Replication lag

```bash
# Check lag on replica
psql -U postgres -c "SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;"

# If lag > 10MB, investigate network or disk I/O
```

### Split-brain prevention

Patroni uses etcd for consensus. As long as:
- 2 out of 3 etcd nodes are healthy
- Patroni can reach etcd

...split-brain is **impossible**. Only one node can hold the leader lease at a time.

## Security Notes

1. **Bind to Tailscale IPs only** - Postgres listens on `0.0.0.0:5432` but only accepts connections from Tailscale subnet
2. **Firewall** - Only allow port 5432 from Tailscale IPs
3. **Strong passwords** - Use 32+ character random passwords
4. **SSL/TLS** - Add `ssl=on` in postgresql.parameters for encrypted connections
5. **pg_hba.conf** - Managed by Patroni, restricts access to Tailscale network

## Performance Tuning

Adjust in `bootstrap.dcs.postgresql.parameters`:

**For 2GB RAM VPS:**
```yaml
shared_buffers: 512MB
effective_cache_size: 1536MB
maintenance_work_mem: 128MB
```

**For 4GB RAM VPS:**
```yaml
shared_buffers: 1GB
effective_cache_size: 3GB
maintenance_work_mem: 256MB
```

## Monitoring

Key metrics to track:

```bash
# Replication lag
SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag_bytes;

# Connection count
SELECT count(*) FROM pg_stat_activity;

# Database size
SELECT pg_size_pretty(pg_database_size('uptrack_prod'));

# Cache hit rate (should be >95%)
SELECT sum(blks_hit)*100/sum(blks_hit+blks_read) AS cache_hit_ratio
FROM pg_stat_database;
```

Add these to Prometheus or your monitoring solution.
