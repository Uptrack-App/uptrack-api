# Uptrack 3-VPS Deployment Plan

**Status**: Draft
**Updated**: 2025-10-09
**Target**: Production-ready HA setup with Postgres + ClickHouse
**Domain**: uptrack.app

---

## 🎯 Deployment Goals

- **High Availability**: Any single node can fail without user impact
- **Cost Efficiency**: 3 VPS instances across separate regions
- **Data Durability**: Postgres HA (Patroni) + ClickHouse with backups
- **Network Security**: Public via Cloudflare (free), private via Tailscale
- **Distributed Job Execution**: Oban runs on all 3 nodes for regional monitoring

---

## 🏗️ Architecture Overview

```
                    Cloudflare DNS (uptrack.app)
                              ↓  ↓  ↓
                    ┌─────────┬─────────┬─────────┐
                    │ Node A  │ Node B  │ Node C  │
                    │ (Region │ (Region │ (Region │
                    │   1)    │   2)    │   3)    │
                    └─────────┴─────────┴─────────┘
                         ↕           ↕           ↕
                    Tailscale Private Network (100.x.x.x)

┌─────────────────────────────────────────────────────────────┐
│ Node A (App + PG Primary + Region 1 Checks)                 │
├─────────────────────────────────────────────────────────────┤
│ • HAProxy :443 → Phoenix :4000                              │
│ • HAProxy :6432 → Postgres Primary (via Patroni)           │
│ • Postgres 16 (Primary candidate)                           │
│ • Patroni + etcd member                                     │
│ • Oban queues: checks(50), webhooks(10), incidents(5)      │
│ • Region: us-east (or your choice)                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Node B (App + PG Replica + Region 2 Checks)                 │
├─────────────────────────────────────────────────────────────┤
│ • HAProxy :443 → Phoenix :4000                              │
│ • HAProxy :6432 → Postgres Primary (via Patroni)           │
│ • Postgres 16 (Replica, streaming replication)             │
│ • Patroni + etcd member                                     │
│ • Oban queues: checks(50), webhooks(10), incidents(5)      │
│ • Region: eu-central (or your choice)                       │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Node C (App + ClickHouse + Region 3 Checks)                 │
├─────────────────────────────────────────────────────────────┤
│ • HAProxy :443 → Phoenix :4000                              │
│ • HAProxy :6432 → Postgres Primary (via Patroni)           │
│ • ClickHouse (single node)                                  │
│ • etcd member (quorum support)                              │
│ • Oban queues: checks(50), webhooks(10), incidents(5)      │
│ • Region: ap-southeast (or your choice)                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Database Strategy

### Postgres Multi-Repo Setup

All 3 repos connect to the **same Postgres cluster**, using **separate schemas**:

| Repo             | Schema    | Purpose                                      | Connected Nodes |
|------------------|-----------|----------------------------------------------|-----------------|
| `AppRepo`        | `app`     | Users, monitors, incidents, status pages     | A, B, C         |
| `ObanRepo`       | `oban`    | Background jobs, scheduling, queue state     | A, B, C         |
| `ResultsRepo`    | `results` | TimescaleDB time-series check results        | A, B, C         |

**Benefits:**
- Clean separation of concerns
- Independent schema migrations
- Separate retention policies (e.g., prune Oban jobs without touching app data)
- Future scalability: can move repos to separate DB clusters later

### ClickHouse (Node C Only)

- **Tables**:
  - `checks_raw` (raw monitoring results)
  - `checks_1h_rollup` (1-hour aggregates via MV)
  - `checks_1d_rollup` (daily aggregates via MV)
- **Resilience**: Batch writes with local disk spooling on failure
- **Backup**: Nightly `BACKUP` → S3/Backblaze via `rclone`

---

## 🌐 Network Architecture

### Public Access (Cloudflare)

- **DNS**: `uptrack.app` → 3 A records (Node A, B, C public IPs)
- **Subdomain**: `app.uptrack.app` (if using subdomain for web app)
- **Proxied**: Orange cloud enabled (DDoS protection, caching, WAF)
- **SSL/TLS**: Cloudflare-managed certificates (Full/Strict mode)
- **Health-based routing** (optional): Remove dead node IPs via CF API

### Private Network (Tailscale)

- **Purpose**: Postgres replication, etcd cluster, ClickHouse writes
- **Addressing**: `100.x.x.x` static IPs
- **Security**: End-to-end encrypted, no public DB ports
- **Direct connection**: Verify `tailscale ping` shows "direct" (not DERP relayed)

---

## 🔄 High Availability Components

### Patroni (Postgres HA)

- **Cluster**: 3-member etcd (A, B, C) for consensus
- **Primary**: Auto-elected (typically Node A initially)
- **Replica**: Streaming replication to Node B
- **Failover**: Automatic promotion in ≤30 seconds if primary dies
- **Local HAProxy**: Each app connects to `127.0.0.1:6432` → current primary

**Connection flow:**
```
Phoenix App → 127.0.0.1:6432 (local HAProxy) → 100.A.A.A:5432 (Primary via Tailscale)
```

### etcd Quorum

- **Members**: Node A, B, C
- **Purpose**: Distributed consensus for Patroni leader election
- **Failure tolerance**: Can lose 1 node and maintain quorum

---

## 🛠️ Oban Job Distribution & Regional Checks

### Why Run Oban on All 3 Nodes?

**Regional monitoring** requires checks to run from different geographic locations:

- **Node A (us-east)**: Monitors US-based endpoints, detects US-specific outages
- **Node B (eu-central)**: Monitors EU-based endpoints, detects EU-specific outages
- **Node C (ap-southeast)**: Monitors APAC-based endpoints, detects APAC-specific outages

This provides **true multi-region monitoring** without needing external services.

### Configuration

```elixir
# config/runtime.exs (production)
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  node: System.get_env("OBAN_NODE_NAME"),  # "node-a", "node-b", "node-c"
  queues: [
    checks: [limit: 50],          # Monitor checks (region-specific)
    webhooks: [limit: 10],         # Webhook deliveries
    incidents: [limit: 5]          # Incident processing
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 604_800},  # 7 days
    Oban.Plugins.Repeater,
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)},
    {Oban.Plugins.Cron, crontab: [
      {"*/30 * * * * *", Uptrack.Monitoring.SchedulerWorker}
    ]}
  ]
```

### Job Distribution Strategy

**Option 1: Region-aware job insertion**
```elixir
# When creating a monitor check job, specify the region
%{monitor_id: id, region: "us-east"}
|> Uptrack.Monitoring.CheckWorker.new(queue: :checks)
|> Oban.insert()
```

**Option 2: Let Oban distribute globally**
- All nodes pull from the same queue
- First available node processes the job
- Simpler but less geographic control

**Recommendation**: Use Option 1 for precise regional control.

### Regional Node Identification

Each node should know its region via environment variable:

```bash
# Node A
OBAN_NODE_NAME=node-a
NODE_REGION=us-east

# Node B
OBAN_NODE_NAME=node-b
NODE_REGION=eu-central

# Node C
OBAN_NODE_NAME=node-c
NODE_REGION=ap-southeast
```

### Job Safety

- **No duplicate execution**: Oban uses PG advisory locks
- **Failover**: If a node dies mid-job, Lifeline plugin rescues orphaned jobs
- **Queue visibility**: Monitor jobs across all nodes via Oban Web dashboard

---

## 📁 File Structure (New Files to Create)

```
uptrack/
├── .mise.toml                          # Local dev tooling (Elixir, Erlang, PG)
├── docs/
│   ├── deployment-plan.md              # This file
│   └── deployment/
│       ├── 01-network-setup.md         # Tailscale + Cloudflare setup
│       ├── 02-database-setup.md        # Patroni + etcd + schema init
│       ├── 03-app-deployment.md        # Phoenix release deployment
│       └── 04-ha-testing.md            # Disaster recovery drills
├── deploy/
│   ├── nixos/
│   │   ├── node-a.nix                  # NixOS config for Node A
│   │   ├── node-b.nix                  # NixOS config for Node B
│   │   ├── node-c.nix                  # NixOS config for Node C
│   │   └── common.nix                  # Shared config
│   ├── patroni/
│   │   ├── patroni-a.yml               # Patroni config for Node A
│   │   └── patroni-b.yml               # Patroni config for Node B
│   ├── haproxy/
│   │   ├── haproxy-edge.cfg            # Edge proxy (443 → 4000)
│   │   └── haproxy-db.cfg              # DB proxy (6432 → PG primary)
│   ├── systemd/
│   │   ├── uptrack.service             # Phoenix app service
│   │   ├── clickhouse-spool-flush.service
│   │   └── clickhouse-spool-flush.timer
│   └── sql/
│       ├── 00-init-schemas.sql         # CREATE SCHEMA app, oban, results
│       ├── 01-timescaledb-setup.sql    # Enable TimescaleDB + hypertables
│       └── 02-oban-migration.sql       # Oban tables (auto from mix)
└── lib/
    └── uptrack/
        ├── clickhouse/
        │   └── resilient_writer.ex     # Batch + spool to disk on failure
        └── monitoring/
            ├── scheduler_worker.ex     # Oban worker for scheduling checks
            └── check_worker.ex         # Oban worker for executing checks
```

---

## 🚀 Phase-by-Phase Deployment

### Phase 0: Pre-Flight Checklist

- [ ] 3 VPS instances provisioned (recommend: Hetzner, DigitalOcean, or Linode)
- [ ] Each VPS in different geographic region (us-east, eu-central, ap-southeast)
- [ ] Each VPS has public IP + SSH access
- [ ] Domain `uptrack.app` registered + Cloudflare account setup
- [ ] Backblaze B2 or S3 bucket for backups

---

### Phase 1: Network Setup (Day 1, ~1-2 hours)

#### 1.1 Install Tailscale (All Nodes)

```bash
# NixOS
nix-shell -p tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up

# Verify direct connection
tailscale ping <other-node>
```

#### 1.2 Cloudflare DNS

1. Add domain `uptrack.app` to Cloudflare
2. Create A records:
   ```
   uptrack.app → Node A public IP (proxied ✓)
   uptrack.app → Node B public IP (proxied ✓)
   uptrack.app → Node C public IP (proxied ✓)
   ```
3. Optional: Create subdomain `app.uptrack.app` with same 3 IPs
4. Enable "Auto Minify" + Basic WAF rules
5. SSL/TLS: Set to "Full (strict)" mode

**Result**: Users reach any healthy node via round-robin DNS.

---

### Phase 2: Database Setup (Day 1-2, ~3-4 hours)

#### 2.1 Install Postgres 16 + TimescaleDB (Nodes A & B)

```bash
# NixOS configuration.nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_16;
  extensions = [ pkgs.timescaledb ];
  settings = {
    shared_preload_libraries = "timescaledb";
    max_connections = 100;
    shared_buffers = "256MB";
    effective_cache_size = "1GB";
    wal_level = "replica";
    max_wal_senders = 5;
    archive_mode = "on";
  };
};
```

#### 2.2 Install etcd (All 3 Nodes)

```bash
# NixOS
services.etcd = {
  enable = true;
  initialCluster = [
    "node-a=http://100.A.A.A:2380"
    "node-b=http://100.B.B.B:2380"
    "node-c=http://100.C.C.C:2380"
  ];
};
```

#### 2.3 Install Patroni (Nodes A & B)

See `deploy/patroni/patroni-{a,b}.yml` for full configs.

**Key settings:**
- `scope: uptrack-pg-cluster`
- `bootstrap.initdb.data-checksums: true`
- `postgresql.parameters.search_path: public`

#### 2.4 Initialize Schemas

```bash
# On Node A (after Patroni elects primary)
psql -U postgres -d uptrack_prod -f deploy/sql/00-init-schemas.sql
psql -U postgres -d uptrack_prod -f deploy/sql/01-timescaledb-setup.sql
```

#### 2.5 Setup pgBackRest (Node A)

```bash
# /etc/pgbackrest/pgbackrest.conf
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=7
repo1-s3-bucket=uptrack-backups
repo1-s3-key=<B2_KEY>
repo1-s3-key-secret=<B2_SECRET>
repo1-s3-endpoint=s3.us-west-002.backblazeb2.com

[uptrack]
pg1-path=/var/lib/postgresql/16/main
```

**Cron**:
```bash
# Full backup daily at 2 AM
0 2 * * * pgbackrest --stanza=uptrack backup --type=full
```

---

### Phase 3: ClickHouse Setup (Day 2, ~1 hour)

#### 3.1 Install ClickHouse (Node C)

```bash
# NixOS
services.clickhouse = {
  enable = true;
  package = pkgs.clickhouse;
};
```

#### 3.2 Create Tables

```sql
-- checks_raw
CREATE TABLE checks_raw (
  timestamp DateTime64(3),
  monitor_id UUID,
  status String,
  response_time_ms UInt32,
  region String,
  status_code Nullable(UInt16),
  error_message Nullable(String)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (monitor_id, timestamp);

-- 1h rollup (materialized view)
CREATE MATERIALIZED VIEW checks_1h_rollup
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (monitor_id, toStartOfHour(timestamp))
AS SELECT
  toStartOfHour(timestamp) as timestamp,
  monitor_id,
  region,
  count() as check_count,
  avg(response_time_ms) as avg_response_time,
  sum(status = 'up') as success_count
FROM checks_raw
GROUP BY monitor_id, region, toStartOfHour(timestamp);
```

#### 3.3 Backup

```bash
# Nightly backup at 3 AM
0 3 * * * clickhouse-client --query="BACKUP DATABASE default TO Disk('backups', 'backup-$(date +\%Y\%m\%d).zip')"
```

---

### Phase 4: Application Deployment (Day 2-3, ~2-3 hours)

#### 4.1 Install HAProxy (All Nodes)

**Edge proxy** (`/etc/haproxy/haproxy-edge.cfg`):
```
frontend https_in
  bind :443 ssl crt /etc/haproxy/certs/site.pem
  default_backend app_local

backend app_local
  mode http
  option httpchk GET /healthz
  server local 127.0.0.1:4000 check inter 5s
```

**DB proxy** (`/etc/haproxy/haproxy-db.cfg`):
```
frontend db_primary
  bind 127.0.0.1:6432
  default_backend pg_primary

backend pg_primary
  mode tcp
  option tcp-check
  server pgA 100.A.A.A:5432 check
  server pgB 100.B.B.B:5432 check backup
```

#### 4.2 Build Phoenix Release

```bash
# Local (or CI)
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release

# Copy to each node
scp _build/prod/rel/uptrack/uptrack-*.tar.gz node-a:/opt/uptrack/
```

#### 4.3 Configure Environment Variables

Create `/opt/uptrack/.env`:

**Node A**:
```bash
DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=app,public
OBAN_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=oban,public
RESULTS_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=results,public
SECRET_KEY_BASE=<run: mix phx.gen.secret>
PHX_HOST=uptrack.app
PHX_SERVER=true
POOL_SIZE=10
OBAN_NODE_NAME=node-a
NODE_REGION=us-east
CLICKHOUSE_HOST=100.C.C.C
CLICKHOUSE_PORT=8123
```

**Node B**:
```bash
# Same as Node A, but:
OBAN_NODE_NAME=node-b
NODE_REGION=eu-central
```

**Node C**:
```bash
# Same as Node A, but:
OBAN_NODE_NAME=node-c
NODE_REGION=ap-southeast
```

#### 4.4 Run Migrations

```bash
# On Node A (or any node)
/opt/uptrack/bin/uptrack eval "Uptrack.Release.migrate()"
```

**Custom release module** (`lib/uptrack/release.ex`):
```elixir
defmodule Uptrack.Release do
  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(:uptrack, :ecto_repos)
  end
end
```

#### 4.5 Start Services (All Nodes)

```bash
sudo systemctl enable --now uptrack
sudo systemctl enable --now haproxy
```

---

### Phase 5: ClickHouse Writer (Day 3, ~1 hour)

Create resilient writer module with disk spooling.

**Location**: `lib/uptrack/clickhouse/resilient_writer.ex`

**Features**:
- Batch up to 200 rows or 1s timeout
- Exponential backoff (200ms → 3s, 5 retries)
- On failure: write to `/var/lib/uptrack/spool/ts=<iso>.sql`
- Systemd timer flushes spool every minute

**Systemd timer** (`deploy/systemd/clickhouse-spool-flush.timer`):
```
[Unit]
Description=Flush ClickHouse spooled writes

[Timer]
OnCalendar=*:*:00
Persistent=true

[Install]
WantedBy=timers.target
```

---

### Phase 6: HA Testing (Day 3, ~1-2 hours)

Run disaster recovery drills to prove HA works.

#### Drill 1: Kill Postgres Primary (Node A)

```bash
# Node A
sudo systemctl stop patroni
```

**Expected**:
- Node B promoted to primary in ≤30s
- App continues serving (connects to new primary via HAProxy)
- Zero downtime for users
- **Oban jobs continue** — Node B and C keep processing

#### Drill 2: Kill App on Node B

```bash
# Node B
sudo systemctl stop uptrack
```

**Expected**:
- Cloudflare routes traffic to Node A & C
- Users still reach healthy app instances
- **Oban jobs redistribute** — Node A and C pick up Node B's workload

#### Drill 3: Kill ClickHouse (Node C)

```bash
# Node C
sudo systemctl stop clickhouse
```

**Expected**:
- Monitor checks continue running on all 3 nodes
- Results spool to disk at `/var/lib/uptrack/spool/`
- When CH comes back, spooled data flushes automatically

#### Drill 4: Reboot Node A

```bash
# Node A
sudo reboot
```

**Expected**:
- Patroni, Postgres, app all restart cleanly
- Node A rejoins cluster (either as primary or replica)
- **Oban jobs resume** on Node A after restart

---

### Phase 7: Monitoring & Alerts (Day 4, ~1 hour)

#### Health Endpoint

Add `GET /healthz` to Phoenix:

```elixir
# lib/uptrack_web/controllers/health_controller.ex
defmodule UptrackWeb.HealthController do
  use UptrackWeb, :controller

  def show(conn, _params) do
    # Check DB write/read
    case Uptrack.AppRepo.query("SELECT 1") do
      {:ok, _} -> json(conn, %{status: "ok", region: System.get_env("NODE_REGION")})
      {:error, _} -> conn |> put_status(503) |> json(%{status: "unhealthy"})
    end
  end
end
```

#### External Monitoring

Use free tier of:
- **BetterStack** (uptime monitoring)
- **Uptime Kuma** (self-hosted)

Monitor:
- `https://uptrack.app/healthz`
- Patroni primary: `curl -s http://127.0.0.1:8008 | jq .role`
- ClickHouse: `echo 'SELECT 1' | clickhouse-client`

#### Tailscale Performance Impact

**Q: Does Tailscale slow down the app?**

**A: No, minimal impact (<1ms overhead) when configured correctly:**

**Why Tailscale is fast:**
- **Direct connections**: Tailscale establishes peer-to-peer connections between nodes (not routed through relay servers)
- **WireGuard protocol**: Modern, kernel-level encryption (faster than OpenVPN/IPSec)
- **No extra hops**: Data flows directly Node A ↔ Node B via encrypted tunnel
- **Low latency**: ~0.5-1ms overhead vs raw TCP (negligible for DB queries)

**Verification:**
```bash
# Check connection type (should say "direct")
tailscale ping node-b
# Output: pong from node-b (100.B.B.B) via [direct] in 1.2ms

# If it says "DERP" (relay), force direct:
tailscale up --advertise-routes=100.64.0.0/10 --accept-routes
```

**Benchmarks (Postgres query over Tailscale):**
- Direct TCP: ~0.8ms latency
- Tailscale: ~1.2ms latency
- **Impact**: +0.4ms (imperceptible to users)

**When Tailscale adds latency:**
- ❌ DERP relay mode (when direct connection fails due to NAT/firewall)
- ✅ Solution: Use VPS instances (always have public IPs) → forces direct mode

**Benefits outweigh tiny overhead:**
- ✅ No public DB ports (huge security win)
- ✅ Encrypted replication traffic
- ✅ Easy cross-region networking
- ✅ No manual VPN config

**Bottom line**: For your 3-VPS setup with public IPs, Tailscale will use direct connections with <1ms overhead. This is **not noticeable** in your app's response times.

#### Alerting Targets

- Email
- Slack webhook
- PagerDuty (if using on-call)

---

## 🔒 Security Hardening (Day 5, ~2 hours)

### Cloudflare

- Enable "Under Attack Mode" during incidents
- Rate limiting: 100 req/min per IP on `/login`
- Challenge Score ≥30 for suspicious traffic

### Postgres

- TLS connections: `ssl=true` in DATABASE_URL
- Firewall: Only Tailscale IPs can connect to `:5432`
- User permissions: App user cannot `DROP DATABASE`

### ClickHouse

- Bind to Tailscale IP only (`listen_host: 100.C.C.C`)
- mTLS or signed JWT for writes (from app)
- Row-level filter: `WHERE monitor_id IN (SELECT id FROM monitors WHERE user_id = ?)`

### OS

- Unattended security updates enabled
- Fail2ban on SSH (10 failed attempts = 1h ban)
- SSH key-only auth (no passwords)

---

## 📦 Environment Variables Reference

### Required for All Nodes

```bash
DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=app,public
OBAN_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=oban,public
RESULTS_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=results,public
SECRET_KEY_BASE=<64-char-secret>
PHX_HOST=uptrack.app
PHX_SERVER=true
POOL_SIZE=10
OBAN_NODE_NAME=<node-a|node-b|node-c>
NODE_REGION=<us-east|eu-central|ap-southeast>
```

### Node C Only (ClickHouse)

```bash
CLICKHOUSE_HOST=100.C.C.C
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default
```

### OAuth (All Nodes)

```bash
GITHUB_CLIENT_ID=<from GitHub OAuth app>
GITHUB_CLIENT_SECRET=<from GitHub OAuth app>
GOOGLE_CLIENT_ID=<from Google Console>
GOOGLE_CLIENT_SECRET=<from Google Console>
```

---

## 🎓 Key Learnings & Best Practices

### Why 3 Repos?

- **Isolation**: Oban jobs won't slow down user queries
- **Scaling**: Can move ObanRepo to larger instance later
- **Maintenance**: Prune job logs without touching app data

### Why Patroni over Manual Failover?

- **Speed**: 30s automatic failover vs. hours of manual work
- **Testing**: Easy to simulate failures with `systemctl stop patroni`
- **Reliability**: Eliminates human error during incidents

### Why Run Oban on All 3 Nodes?

- **Regional monitoring**: Each node monitors from its geographic region
- **True multi-region checks**: Detect region-specific outages (e.g., CDN fails in EU but works in US)
- **No external services**: No need for paid multi-region monitoring tools
- **High availability**: If one node dies, other 2 continue monitoring

### Why ClickHouse on Separate Node?

- **Resource isolation**: CH aggregations won't starve Postgres
- **Independent failure**: CH downtime doesn't break app
- **Cost optimization**: Can use cheaper VPS for CH node

---

## 📋 Maintenance Checklists

### Weekly

- [ ] Review Oban failed jobs: `Oban.Job |> where([j], j.state == "failed") |> Repo.all()`
- [ ] Check Patroni replication lag: `SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn();`
- [ ] Verify backups: `pgbackrest info` and `rclone ls b2:uptrack-backups`
- [ ] Verify all 3 nodes processing Oban jobs: Check `/admin/oban` dashboard

### Monthly

- [ ] Rotate Postgres logs
- [ ] Review ClickHouse disk usage: `du -sh /var/lib/clickhouse`
- [ ] Test restore from backup (in staging)
- [ ] Review Cloudflare analytics for anomalies
- [ ] Verify regional checks working from all 3 nodes

### Quarterly

- [ ] Run full HA drill (all 4 scenarios)
- [ ] Security audit (check for CVEs in deps)
- [ ] Review and optimize slow queries
- [ ] Load test regional failover (kill one region, ensure others compensate)

---

## 🆘 Troubleshooting

### Patroni Won't Start

```bash
# Check etcd cluster health
etcdctl endpoint health --cluster

# View Patroni logs
journalctl -u patroni -f

# Common fix: Clear stale data
rm -rf /var/lib/postgresql/16/main
patronictl reinit uptrack-pg-cluster node-a
```

### App Can't Connect to DB

```bash
# Test HAProxy
curl -v http://127.0.0.1:6432

# Test direct connection
psql -h 100.A.A.A -U uptrack -d uptrack_prod

# Check Patroni primary
curl -s http://127.0.0.1:8008 | jq .role
```

### ClickHouse Writes Failing

```bash
# Check spool directory
ls -lh /var/lib/uptrack/spool/

# Manually flush
for f in /var/lib/uptrack/spool/*.sql; do
  clickhouse-client --multiquery < "$f" && rm "$f"
done

# Check CH logs
journalctl -u clickhouse -f
```

### Oban Jobs Not Running on a Node

```bash
# Check Oban status
/opt/uptrack/bin/uptrack remote
iex> Oban.check_queue(:checks)

# View logs
journalctl -u uptrack -f | grep Oban

# Verify NODE_REGION is set
echo $NODE_REGION
```

---

## 🚢 Next Steps After Deployment

1. **Set up staging environment** (single VPS, same schema structure)
2. **CI/CD pipeline** (GitHub Actions → deploy to all 3 nodes)
3. **Observability**: Add Prometheus + Grafana for metrics
4. **Oban Web Dashboard**: Enable `/admin/oban` for job monitoring
5. **Cost tracking**: Tag VPS instances for monthly cost review
6. **Documentation**: Record all passwords in 1Password/Bitwarden

---

## 📚 References

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Oban Documentation](https://hexdocs.pm/oban/)
- [Oban Pro (optional upgrade)](https://getoban.pro/)
- [TimescaleDB Best Practices](https://docs.timescale.com/use-timescale/latest/)
- [Cloudflare DNS API](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-create-dns-record)
- [Tailscale Admin Console](https://login.tailscale.com/admin/)

---

## ✅ Definition of Done

The deployment is **production-ready** when:

- ✅ All 3 nodes are reachable via `https://uptrack.app`
- ✅ HAProxy shows all backends healthy
- ✅ Patroni shows 1 primary + 1 replica
- ✅ **Oban processes jobs on all 3 nodes** (verify in dashboard)
- ✅ **Regional checks working** (each node reports its region correctly)
- ✅ ClickHouse writes succeed (or spool on failure)
- ✅ All 4 HA drills pass successfully
- ✅ Daily backups running + verified restorable
- ✅ External monitoring pings `/healthz` every 1 min
- ✅ SSL certificates valid (Cloudflare-managed)
- ✅ No errors in logs for 24 hours

---

**End of Deployment Plan**
