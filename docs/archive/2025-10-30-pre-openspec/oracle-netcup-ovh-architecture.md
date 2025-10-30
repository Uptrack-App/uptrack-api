# Uptrack Infrastructure: Oracle + Netcup Architecture

**Status**: Recommended
**Updated**: 2025-10-10
**Total Cost**: €10-11/month
**Coverage**: 2 continents (APAC, EU)

---

## 🎯 Architecture Overview

This architecture maximizes Oracle Cloud's Always Free tier while strategically using Netcup for European coverage and high availability.

### Core Principle: Separate Primary Databases

**Key Design Decision**: PostgreSQL PRIMARY and ClickHouse PRIMARY run on **different nodes** to eliminate single point of failure.

```
┌─────────────────────────────────────────────────┐
│ Node A: Oracle Cloud Mumbai (FREE)              │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ POSTGRES PRIMARY ONLY                            │
├─────────────────────────────────────────────────┤
│ • 4 ARM cores, 24 GB RAM, 200 GB NVMe           │
│ • PostgreSQL PRIMARY + Patroni                   │
│ • Phoenix app + Oban                             │
│ • etcd member                                    │
│ • Region: ap-south (India)                       │
│ • NODE_REGION=ap-south                          │
│                                                  │
│ Services:                                        │
│ ✅ Postgres Primary (all writes)                │
│ ✅ APAC regional monitoring checks               │
│ ✅ Web endpoint via Cloudflare                   │
│                                                  │
│ Resources:                                       │
│ ├─ Postgres: 12-14 GB RAM, 2-3 cores            │
│ ├─ Phoenix: 2 GB RAM, 1 core                    │
│ ├─ Oban: 1 GB RAM, 1 core                       │
│ └─ FREE: 9 GB RAM unused (37% spare!)           │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Node B: Netcup Germany (€5.26/mo)              │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ CLICKHOUSE PRIMARY + POSTGRES REPLICA            │
├─────────────────────────────────────────────────┤
│ • 6 vCores, 12 GB RAM, 100 GB SSD NVMe          │
│ • ClickHouse PRIMARY                             │
│ • PostgreSQL REPLICA (streaming replication)    │
│ • Phoenix app + Oban                             │
│ • etcd member                                    │
│ • Region: eu-central (Germany)                   │
│ • NODE_REGION=eu-central                        │
│                                                  │
│ Services:                                        │
│ ✅ ClickHouse Primary (all monitoring writes)   │
│ ✅ Postgres Replica (can be promoted)           │
│ ✅ EU regional monitoring checks                 │
│ ✅ Web endpoint via Cloudflare                   │
│                                                  │
│ Resources:                                       │
│ ├─ ClickHouse: 5 GB RAM, 2-3 cores              │
│ ├─ Postgres replica: 3 GB RAM, 1-2 cores        │
│ ├─ Phoenix: 2 GB RAM, 1 core                    │
│ └─ Comfortable fit (~12 GB total)               │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Node C: Netcup Germany (€5.26/mo)              │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ CLICKHOUSE REPLICA ONLY                          │
├─────────────────────────────────────────────────┤
│ • 6 vCores, 8 GB RAM, 100 GB SSD NVMe           │
│ • ClickHouse REPLICA                             │
│ • Phoenix app + Oban                             │
│ • etcd member (quorum)                           │
│ • Region: eu-west (Germany)                      │
│ • NODE_REGION=eu-west                           │
│                                                  │
│ Services:                                        │
│ ✅ ClickHouse Replica (serves EU reads)         │
│ ✅ EU regional monitoring checks (backup)        │
│ ✅ Web endpoint via Cloudflare                   │
│ ✅ ClickHouse HA backup                         │
│                                                  │
│ Resources:                                       │
│ ├─ ClickHouse replica: 4 GB RAM, 2 cores        │
│ ├─ Phoenix: 2 GB RAM, 1 core                    │
│ └─ Good headroom (2 GB free)                    │
└─────────────────────────────────────────────────┘
```

---

## 💰 Cost Breakdown

| Node | Provider | Specs | Services | Cost |
|------|----------|-------|----------|------|
| **A** | Oracle Mumbai | 4 ARM, 24 GB, 200 GB | Postgres PRIMARY | **FREE** |
| **B** | Netcup Germany | 6 ARM, 8 GB, 252 GB | ClickHouse PRIMARY + PG Replica | **€5.26** |
| **C** | OVH Virginia | 4-6 vCPU, 8-12 GB, 80-100 GB | ClickHouse REPLICA | **€6-8** |

**Total Monthly Cost**: €11-13 (~$12-14)

**Annual Cost**: €132-156 (~$144-170)

---

## 🌍 Regional Coverage

| Region | Node | Latency | Coverage |
|--------|------|---------|----------|
| **India** | Oracle Mumbai | <20ms | India, Pakistan, Bangladesh |
| **Southeast Asia** | Oracle Mumbai | 50-100ms | Singapore, Thailand, Malaysia |
| **Middle East** | Oracle Mumbai | 80-120ms | UAE, Saudi Arabia, Israel |
| **Europe** | Netcup Germany | <30ms | Germany, France, Poland, Netherlands |
| **UK** | Netcup Germany | 30-50ms | United Kingdom, Ireland |
| **Africa** | Netcup Germany | 100-150ms | South Africa, Egypt |
| **US East** | OVH Virginia | <20ms | New York, Washington DC, Atlanta |
| **US West** | OVH Virginia | 60-80ms | California, Oregon |
| **Canada** | OVH Virginia | 30-50ms | Toronto, Montreal |
| **South America** | OVH Virginia | 150-200ms | Brazil, Argentina |

**Coverage**: ~70% of global internet users with <150ms latency

---

## 🔄 High Availability & Failover

### PostgreSQL HA (Patroni Cluster)

**Normal State:**
- Primary: Oracle Mumbai
- Replica: Netcup Germany
- Streaming replication lag: <100ms

**Failure Scenarios:**

| Failure | Automatic Response | Recovery Time | User Impact |
|---------|-------------------|---------------|-------------|
| **Oracle dies** | Netcup promoted to primary via Patroni | ≤30 seconds | Zero downtime (automatic failover) |
| **Netcup dies** | Oracle continues as primary | 0 seconds | Zero downtime (reads from primary) |
| **Network partition** | etcd maintains quorum, Patroni decides primary | ≤30 seconds | Zero downtime |

**Patroni Configuration:**
```yaml
# /etc/patroni/patroni.yml
scope: uptrack-pg-cluster
namespace: /service/
name: node-a  # or node-b

restapi:
  listen: 127.0.0.1:8008
  connect_address: 100.64.0.1:8008

etcd:
  hosts: 100.64.0.1:2379,100.64.0.2:2379,100.64.0.3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576

postgresql:
  use_pg_rewind: true
  parameters:
    max_connections: 100
    shared_buffers: 4GB
    effective_cache_size: 12GB
    wal_level: replica
    max_wal_senders: 5
```

### ClickHouse HA (Replication)

**Normal State:**
- Primary: Netcup Germany (writes)
- Replica: OVH Virginia (reads + backup)
- Replication lag: <1 second

**Failure Scenarios:**

| Failure | Automatic Response | Recovery Time | User Impact |
|---------|-------------------|---------------|-------------|
| **Netcup dies** | Writes fail, reads from OVH replica | ~1-2 minutes | Analytics read-only, monitoring continues |
| **OVH dies** | All queries go to Netcup | 0 seconds | Zero impact |
| **Both die** | Monitoring data spools to disk on all Phoenix nodes | 0 seconds | Zero impact (spooled writes) |

**ClickHouse Replication:**
```sql
-- On both Netcup and OVH
CREATE TABLE checks_raw ON CLUSTER '{cluster}'
(
    timestamp DateTime64(3),
    monitor_id UUID,
    region String,
    status String,
    response_time_ms UInt32,
    status_code Nullable(UInt16),
    error_message Nullable(String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/checks_raw', '{replica}')
PARTITION BY toYYYYMM(timestamp)
ORDER BY (monitor_id, timestamp)
SETTINGS index_granularity = 8192;
```

---

## 📊 Resource Allocation Details

### Node A (Oracle - Postgres Primary)

**Total Resources**: 4 ARM cores, 24 GB RAM, 200 GB NVMe

```yaml
PostgreSQL:
  memory: 12-14 GB
  cores: 2-3
  settings:
    shared_buffers: 4GB
    effective_cache_size: 12GB
    maintenance_work_mem: 1GB
    max_connections: 100

Phoenix App:
  memory: 2 GB
  cores: 1
  instances: 1

Oban Workers:
  memory: 1 GB
  cores: 1
  queues:
    - checks: 50 workers
    - webhooks: 10 workers
    - incidents: 5 workers

System (OS, monitoring):
  memory: 500 MB

Total Used: ~15-16 GB RAM, 4 cores
Spare Capacity: 8-9 GB RAM (37% free for growth!)
```

### Node B (Netcup - ClickHouse Primary + Postgres Replica)

**Total Resources**: 6 ARM cores, 8 GB RAM, 252 GB NVMe

```yaml
ClickHouse:
  memory: 3.5 GB
  cores: 2-3
  settings:
    max_memory_usage: 3500000000  # 3.5 GB
    max_server_memory_usage: 3500000000

PostgreSQL Replica:
  memory: 2 GB
  cores: 1-2
  settings:
    shared_buffers: 512MB
    effective_cache_size: 1.5GB
    hot_standby: on

Phoenix App:
  memory: 1.5 GB
  cores: 1

Oban Workers:
  memory: 500 MB
  queues:
    - checks: 50 workers
    - webhooks: 10 workers

System:
  memory: 500 MB

Total Used: ~8 GB RAM, 6 cores
Spare Capacity: Minimal (tight but workable)
```

### Node C (OVH - ClickHouse Replica)

**Total Resources**: 4-6 vCPU, 8-12 GB RAM, 80-100 GB NVMe

```yaml
ClickHouse Replica:
  memory: 4-5 GB
  cores: 2
  role: Read queries + failover backup

Phoenix App:
  memory: 1.5 GB
  cores: 1

Oban Workers:
  memory: 500 MB
  queues:
    - checks: 50 workers

System:
  memory: 500 MB

Total Used: ~6.5-7 GB RAM, 3-4 cores
Spare Capacity: 1.5-5.5 GB RAM
```

---

## 🔧 Network Architecture & Load Balancing

### Why NOT Oracle Load Balancer?

**Oracle's Network Load Balancer (even in Always Free tier) can ONLY balance between Oracle Cloud instances in the same VCN.**

Since our nodes are on different cloud providers:
- ❌ Oracle LB cannot reach Netcup servers
- ❌ Oracle LB cannot balance across multiple clouds
- ❌ Not useful for this multi-cloud setup

### Load Balancing Options (All FREE)

#### Option 1: Cloudflare DNS Round-Robin (Recommended, FREE)

**You already have this with Cloudflare's FREE tier - no need to pay for Cloudflare Load Balancer!**

```
Users Worldwide
    ↓
Cloudflare FREE tier (DDoS, WAF, CDN, SSL)
    ↓
DNS returns all 3 IPs (round-robin):
    ├─ Oracle Mumbai IP (e.g., 150.136.x.x)
    ├─ Netcup Germany IP #1 (e.g., 45.138.x.x)
    └─ Netcup Germany IP #2 (e.g., 45.138.x.x)
```

**Setup in Cloudflare (FREE):**
```
1. Add 3 A records with same name:
   uptrack.app  A  150.136.x.x  (Oracle Mumbai) - Proxied (orange cloud)
   uptrack.app  A  45.138.x.x   (Netcup B) - Proxied (orange cloud)
   uptrack.app  A  45.138.x.x   (Netcup C) - Proxied (orange cloud)

2. Enable proxy (orange cloud icon) on all records
3. Done! Cloudflare will distribute traffic automatically
```

**How it works:**
- Cloudflare distributes requests across all 3 IPs
- If one node is down, Cloudflare removes it from rotation (health checks)
- Built-in DDoS protection + CDN
- **Cost: $0/month**

#### Option 2: HAProxy on Oracle Node (Advanced, FREE)

Use Oracle's spare resources (9 GB free RAM) to run HAProxy as entry point:

```
Users Worldwide
    ↓
Cloudflare → Only Oracle Mumbai IP
                ↓
    HAProxy on Oracle (local, uses spare RAM)
                ↓
        Balances to 3 Phoenix backends via Tailscale:
        ├─ 100.64.0.1:4000 (Oracle - local, 0ms)
        ├─ 100.64.0.2:4000 (Netcup B - via Tailscale, ~120ms)
        └─ 100.64.0.3:4000 (Netcup C - via Tailscale, ~120ms)
```

**HAProxy config (on Oracle node):**
```haproxy
# /etc/haproxy/haproxy.cfg
frontend https_frontend
    bind *:443 ssl crt /etc/ssl/uptrack.pem
    default_backend phoenix_servers

backend phoenix_servers
    balance roundrobin
    option httpchk GET /healthz
    http-check expect status 200

    server node-a 100.64.0.1:4000 check inter 5s fall 3 rise 2
    server node-b 100.64.0.2:4000 check inter 5s fall 3 rise 2
    server node-c 100.64.0.3:4000 check inter 5s fall 3 rise 2
```

**Pros:**
- Advanced health checks
- Smart load balancing (least connections, sticky sessions)
- Uses Oracle's free spare RAM
- **Cost: $0/month**

**Cons:**
- Oracle becomes single entry point (but has 99.95% SLA)
- APAC users get best latency, but EU/US users go through India first (+100ms)

### Recommended Approach: Option 1 (Cloudflare DNS)

Use **Cloudflare's FREE tier DNS round-robin** because:
- ✅ Zero cost
- ✅ Simple setup (just add 3 A records)
- ✅ Global distribution (Cloudflare picks nearest node for users)
- ✅ Automatic failover (removes unhealthy nodes)
- ✅ DDoS protection included
- ✅ No single point of failure

### External (Cloudflare DNS Round-Robin - FREE)

```
Users Worldwide
    ↓
Cloudflare FREE tier
├─ DDoS protection
├─ WAF (Web Application Firewall)
├─ CDN
├─ SSL/TLS
└─ DNS round-robin (automatic load balancing)
    ↓
Distributes to 3 nodes:
    ├─ Oracle Mumbai IP
    ├─ Netcup Germany IP #1
    └─ Netcup Germany IP #2
```

### Internal (Tailscale Private Network)

```
All nodes connected via Tailscale:
├─ Oracle Mumbai: 100.64.0.1
├─ Netcup Germany: 100.64.0.2
└─ OVH Virginia: 100.64.0.3

Database Connections (over Tailscale):
├─ Phoenix → Postgres: 100.64.0.1:5432 (via HAProxy)
├─ Phoenix → ClickHouse: 100.64.0.2:8123 (primary)
└─ Backup ClickHouse: 100.64.0.3:8123 (replica)

etcd Cluster (over Tailscale):
├─ Member 1: 100.64.0.1:2379
├─ Member 2: 100.64.0.2:2379
└─ Member 3: 100.64.0.3:2379
```

---

## 🚀 Deployment Instructions

### Phase 1: Provision Servers

**Oracle Cloud (FREE):**
1. Login to Oracle Cloud Console
2. Choose Mumbai (ap-mumbai-1) or Hyderabad (ap-hyderabad-1) as home region
3. Create VM Instance:
   - Shape: VM.Standard.A1.Flex
   - OCPUs: 4 (use all free cores)
   - Memory: 24 GB (use all free RAM)
   - Boot Volume: 200 GB
   - Image: Ubuntu 24.04 LTS ARM64
   - Networking: Create new VCN (will be Always Free)

**Netcup ARM G11:**
1. Visit https://www.netcup.com/en/server/arm-server/
2. Order: VPS 1000 ARM G11 (Nuremberg or Vienna)
3. Price: €5.26/month
4. Specs: 6 ARM cores, 8 GB RAM, 252 GB NVMe

**OVH VPS:**
1. Visit https://www.ovhcloud.com/en/vps/
2. Choose location: Virginia (VIN-1) or Canada (BHS)
3. Choose plan with 4+ vCPU, 8+ GB RAM
4. Expected price: €6-8/month

### Phase 2: Configure Cloudflare DNS (Load Balancing)

**This is your FREE load balancer - no need to buy Oracle LB or Cloudflare's paid LB!**

1. Login to Cloudflare dashboard
2. Select your domain: `uptrack.app`
3. Go to DNS → Records
4. Add 3 A records (all with same name):

```
Type: A
Name: @
Content: <Oracle Mumbai IP>    (e.g., 150.136.x.x)
Proxy status: Proxied (orange cloud icon)
TTL: Auto

Type: A
Name: @
Content: <Netcup Germany B IP> (e.g., 45.138.x.x)
Proxy status: Proxied (orange cloud icon)
TTL: Auto

Type: A
Name: @
Content: <Netcup Germany C IP> (e.g., 45.138.x.x)
Proxy status: Proxied (orange cloud icon)
TTL: Auto
```

5. Verify all 3 records are **Proxied** (orange cloud, not gray)
6. Done! Cloudflare will automatically:
   - Distribute traffic across all 3 IPs
   - Remove unhealthy nodes from rotation
   - Provide DDoS protection
   - Serve via CDN

**Cost: $0/month** ✅

### Phase 3: Install Tailscale (All Nodes)

```bash
# On each node
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --accept-routes

# Get Tailscale IPs
tailscale ip -4
# Note down the IP for each node (100.64.0.x)

# Verify direct connection
tailscale ping <other-node-hostname>
# Should say "direct" not "DERP"
```

### Phase 4: Install etcd (All Nodes)

**Node A (Oracle):**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install etcd-server etcd-client

# Configure /etc/default/etcd
ETCD_NAME="node-a"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="http://100.64.0.1:2380"
ETCD_LISTEN_CLIENT_URLS="http://100.64.0.1:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://100.64.0.1:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://100.64.0.1:2379"
ETCD_INITIAL_CLUSTER="node-a=http://100.64.0.1:2380,node-b=http://100.64.0.2:2380,node-c=http://100.64.0.3:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="uptrack-cluster"

sudo systemctl enable --now etcd
```

**Repeat for Node B and Node C** (adjust IPs and names)

**Verify cluster:**
```bash
etcdctl endpoint health --cluster
```

### Phase 5: Install PostgreSQL + Patroni (Nodes A & B)

**Node A (Oracle - Primary):**
```bash
# Install PostgreSQL 16
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt update
sudo apt install postgresql-16 postgresql-server-dev-16

# Install Patroni
sudo apt install python3-pip python3-psycopg2
sudo pip3 install patroni[etcd]

# Stop default PostgreSQL
sudo systemctl stop postgresql
sudo systemctl disable postgresql

# Configure Patroni (see patroni.yml above)
sudo systemctl enable --now patroni
```

**Node B (Netcup - Replica):**
Same steps, ensure `name: node-b` in patroni.yml

**Verify cluster:**
```bash
sudo patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster
```

Expected output:
```
+ Cluster: uptrack-pg-cluster ----+---------+----+-----------+
| Member | Host        | Role    | State   | TL | Lag in MB |
+--------+-------------+---------+---------+----+-----------+
| node-a | 100.64.0.1  | Leader  | running |  1 |           |
| node-b | 100.64.0.2  | Replica | running |  1 |         0 |
+--------+-------------+---------+---------+----+-----------+
```

### Phase 6: Install ClickHouse (Nodes B & C)

**Node B (Netcup - Primary):**
```bash
# Install ClickHouse
sudo apt install -y apt-transport-https ca-certificates dirmngr
GNUPGHOME=$(mktemp -d)
sudo GNUPGHOME="$GNUPGHOME" gpg --no-default-keyring --keyring /usr/share/keyrings/clickhouse-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 8919F6BD2B48D754
rm -rf "$GNUPGHOME"
sudo chmod +r /usr/share/keyrings/clickhouse-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] https://packages.clickhouse.com/deb stable main" | sudo tee /etc/apt/sources.list.d/clickhouse.list
sudo apt update
sudo apt install -y clickhouse-server clickhouse-client

# Configure for replication
sudo nano /etc/clickhouse-server/config.xml
# Set listen_host to Tailscale IP: <listen_host>100.64.0.2</listen_host>

sudo systemctl enable --now clickhouse-server
```

**Node C (OVH - Replica):**
Same steps, adjust listen_host to `100.64.0.3`

**Setup replication:**
```sql
-- On Node B (primary)
CREATE DATABASE uptrack;

-- Create replicated table
CREATE TABLE uptrack.checks_raw ON CLUSTER '{cluster}'
(
    timestamp DateTime64(3),
    monitor_id UUID,
    region String,
    status String,
    response_time_ms UInt32,
    status_code Nullable(UInt16),
    error_message Nullable(String)
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/checks_raw', '{replica}')
PARTITION BY toYYYYMM(timestamp)
ORDER BY (monitor_id, timestamp);

-- Verify replication on Node C
-- Data should appear automatically
```

### Phase 7: Deploy Phoenix Application (All Nodes)

```bash
# Build release locally or in CI
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Copy to each node
scp _build/prod/rel/uptrack/uptrack-*.tar.gz user@node-a:/opt/uptrack/
scp _build/prod/rel/uptrack/uptrack-*.tar.gz user@node-b:/opt/uptrack/
scp _build/prod/rel/uptrack/uptrack-*.tar.gz user@node-c:/opt/uptrack/

# Extract and configure on each node
cd /opt/uptrack
tar xzf uptrack-*.tar.gz
```

**Environment variables:**

**Node A (Oracle):**
```bash
# /opt/uptrack/.env
DATABASE_URL=postgresql://uptrack:PASSWORD@100.64.0.1:5432/uptrack_prod
OBAN_DATABASE_URL=postgresql://uptrack:PASSWORD@100.64.0.1:5432/uptrack_prod?search_path=oban
RESULTS_DATABASE_URL=postgresql://uptrack:PASSWORD@100.64.0.1:5432/uptrack_prod?search_path=results
CLICKHOUSE_HOST=100.64.0.2
CLICKHOUSE_PORT=8123
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=uptrack.app
PHX_SERVER=true
OBAN_NODE_NAME=node-a
NODE_REGION=ap-south
```

**Node B (Netcup):**
```bash
# Same as Node A, but:
OBAN_NODE_NAME=node-b
NODE_REGION=eu-central
```

**Node C (OVH):**
```bash
# Same as Node A, but:
OBAN_NODE_NAME=node-c
NODE_REGION=us-east
CLICKHOUSE_HOST=100.64.0.3  # Can use local ClickHouse
```

**Start services:**
```bash
# Create systemd service
sudo nano /etc/systemd/system/uptrack.service

[Unit]
Description=Uptrack Monitoring Service
After=network.target

[Service]
Type=simple
User=uptrack
WorkingDirectory=/opt/uptrack
EnvironmentFile=/opt/uptrack/.env
ExecStart=/opt/uptrack/bin/uptrack start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target

# Enable and start
sudo systemctl enable --now uptrack
```

---

## 🧪 Testing & Verification

### Test PostgreSQL HA

```bash
# Check cluster status
sudo patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster

# Test failover
# On Node A (current primary)
sudo systemctl stop patroni

# Wait 30 seconds, then check cluster
# On Node B
sudo patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster
# Node B should now be Leader

# Restart Node A
sudo systemctl start patroni
# Node A should rejoin as Replica
```

### Test ClickHouse Replication

```bash
# On Node B (primary), insert test data
echo "INSERT INTO uptrack.checks_raw VALUES (now(), 'test-uuid', 'eu-central', 'up', 150, 200, NULL)" | clickhouse-client

# On Node C (replica), verify
echo "SELECT * FROM uptrack.checks_raw WHERE monitor_id = 'test-uuid'" | clickhouse-client
# Should show the same data
```

### Test Regional Monitoring

```bash
# Create a monitor via Phoenix web UI or API
# Enable regions: ap-south, eu-central, us-east

# Wait 1-2 minutes, then check ClickHouse
echo "SELECT region, count(*) FROM uptrack.checks_raw WHERE monitor_id = '<your-monitor-id>' GROUP BY region" | clickhouse-client

# Expected output:
┌─region────────┬─count()─┐
│ ap-south      │      3  │
│ eu-central    │      3  │
│ us-east       │      3  │
└───────────────┴─────────┘
```

---

## 📈 Monitoring & Maintenance

### Health Checks

```bash
# Check all services
for node in node-a node-b node-c; do
  echo "=== $node ==="
  curl -s https://uptrack.app/healthz | jq .
done
```

### Weekly Tasks

- [ ] Check Patroni replication lag: `SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn();`
- [ ] Verify ClickHouse replication: Compare row counts between primary and replica
- [ ] Review Oban failed jobs: Check `/admin/oban` dashboard
- [ ] Check disk usage on all nodes

### Monthly Tasks

- [ ] Review and optimize slow queries
- [ ] Check for PostgreSQL bloat
- [ ] Verify backups are restorable
- [ ] Update security patches

---

## 💪 Scaling Path

### When to Scale Up

**Add More Regions (€3-5 each):**
```
Node D: Vultr Tokyo (€3.50)
Node E: Vultr Sydney (€5)
Node F: Vultr Sao Paulo (€5)

Total: €24-26/month for 6-region coverage
```

**Upgrade Node B (if tight on RAM):**
```
Current: Netcup ARM G11 (6 cores, 8 GB) - €5.26
Upgrade: Netcup VPS 2000 ARM G11 (8 cores, 16 GB) - €10.52

Gives ClickHouse + Postgres more breathing room
```

**Add ClickHouse Cluster (horizontal scaling):**
```
Split ClickHouse across multiple nodes
Use distributed tables
Cost: +€5-10/month per shard
```

---

## 🆘 Troubleshooting

### Patroni Won't Start

```bash
# Check etcd cluster
etcdctl endpoint health --cluster

# View logs
journalctl -u patroni -f

# Common fix: clear stale data
sudo systemctl stop patroni
sudo rm -rf /var/lib/postgresql/16/main/*
sudo systemctl start patroni
```

### ClickHouse Replication Lag

```bash
# Check replication lag
echo "SELECT database, table, replica_name, absolute_delay FROM system.replicas" | clickhouse-client

# If lag > 10 seconds, check network
tailscale status
```

### Node Running Out of Memory

```bash
# Check memory usage
free -h
top

# If Node B (Netcup) is tight:
# Option 1: Reduce ClickHouse memory limit
# Option 2: Upgrade to VPS 2000 ARM G11 (€10.52)
```

---

## 📚 References

- [Oracle Cloud Always Free Documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [ClickHouse Replication](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication)
- [Tailscale Setup Guide](https://tailscale.com/kb/1017/install/)
- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)

---

## ✅ Success Criteria

Deployment is complete when:

- ✅ All 3 nodes reachable via `https://uptrack.app`
- ✅ Patroni shows 1 primary (Oracle) + 1 replica (Netcup)
- ✅ ClickHouse replication working (primary: Netcup, replica: OVH)
- ✅ Oban processing jobs on all 3 nodes
- ✅ Regional checks working from 3 continents
- ✅ All health checks passing
- ✅ Failover tests successful (Postgres and ClickHouse)
- ✅ No errors in logs for 24 hours

**Total Cost: €11-13/month for production-ready HA setup across 3 continents!** 🚀
