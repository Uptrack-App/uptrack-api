# PostgreSQL Architecture Design

## Overview

This document details the PostgreSQL architecture using Citus for horizontal scaling, Patroni for high availability, and pgBackRest for backups to Backblaze B2. All components are deployed on NixOS.

---

## Architecture Diagram

### Citus Cluster Topology

```
CITUS DISTRIBUTED CLUSTER (Netcup Nuremberg - <5ms inter-node latency)
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ nbg-1: Coordinator (Primary)                                     │   │
│  │ • Citus coordinator (query routing, metadata)                    │   │
│  │ • pg_dist_* tables (shard metadata)                             │   │
│  │ • Oban tables (LOCAL - not distributed)                         │   │
│  │ • Reference tables (replicated to all workers)                   │   │
│  │ • Patroni (leader election via etcd)                            │   │
│  │ • etcd (1/3)                                                     │   │
│  │ • pgBackRest (stanza: coordinator)                              │   │
│  │ Tailscale: 100.64.1.1                                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                          │                                              │
│            ┌─────────────┴─────────────┐                               │
│            │   Distributed Queries     │                               │
│            ▼                           ▼                               │
│  ┌─────────────────────────┐  ┌─────────────────────────┐             │
│  │ nbg-2: Worker 1         │  │ nbg-3: Worker 2         │             │
│  │ • Citus worker          │  │ • Citus worker          │             │
│  │ • Shards 1,3,5,7...     │  │ • Shards 2,4,6,8...     │             │
│  │ • Distributed data      │  │ • Distributed data      │             │
│  │ • etcd (2/3)            │  │ • etcd (3/3)            │             │
│  │ • pgBackRest (stanza:   │  │ • pgBackRest (stanza:   │             │
│  │   worker1)              │  │   worker2)              │             │
│  │ Tailscale: 100.64.1.2   │  │ Tailscale: 100.64.1.3   │             │
│  └─────────────────────────┘  └─────────────────────────┘             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ WAL archiving
                                    ▼
                    ┌───────────────────────────────┐
                    │       Backblaze B2            │
                    │  s3://uptrack-pgbackrest/     │
                    │  ├── coordinator/             │
                    │  ├── worker1/                 │
                    │  └── worker2/                 │
                    └───────────────────────────────┘
```

### The Challenge: Multi-Node Backups

**Each node has its own WAL stream** - you MUST backup ALL nodes independently:

```
┌─────────────────────────────────────────────────────────────────┐
│ nbg-1: Coordinator                                               │
│ • Metadata (pg_dist_* tables)                                   │
│ • Query routing                                                  │
│ • Oban tables (local)                                           │
│ • Reference tables (replicated)                                  │
└─────────────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────────┐      ┌─────────────────────┐
│ nbg-2: Worker 1     │      │ nbg-3: Worker 2     │
│ • Shard 1,3,5...    │      │ • Shard 2,4,6...    │
│ • Distributed data  │      │ • Distributed data  │
└─────────────────────┘      └─────────────────────┘
```

**Each node has its own WAL stream** - you need to backup ALL nodes.

For consistent cluster restore, all nodes must be restored to the **same point-in-time**.

---

## Key Design Decisions

### 1. Why Citus from Day One (Not Later)?

**Decision:** Deploy Citus immediately rather than retrofitting later.

**Rationale:**
- Adding `organization_id` to all tables later requires:
  - Data migration with downtime
  - Foreign key redesign
  - Query pattern changes throughout codebase
- Starting with Citus is same cost (uses existing nodes)
- Schema designed for distribution from day one

**Trade-offs:**
- Slightly more complex initial setup
- Must include `organization_id` in all tenant queries
- Citus-specific query patterns (co-located JOINs)

### 2. Why Patroni for Coordinator HA?

**Decision:** Use Patroni for automatic coordinator failover.

**Rationale:**
- Coordinator is single point of failure for queries
- Patroni provides automatic leader election via etcd
- <30 second failover RTO
- Well-tested with Citus

**Architecture:**
```
Coordinator HA (Future Enhancement)
┌─────────────────────────────────────────────────────────────────┐
│ nbg-1: Coordinator Primary                                       │
│        ↓ streaming replication                                   │
│ nbg-X: Coordinator Standby (future - requires 4th node)         │
└─────────────────────────────────────────────────────────────────┘
```

**Phase 1:** Single coordinator (acceptable risk for initial deployment)
**Phase 2:** Add coordinator standby when budget allows

### 3. Why pgBackRest over WAL-G?

**Decision:** Use pgBackRest for backups.

**Rationale:**

| Feature | WAL-G | pgBackRest |
|---------|-------|------------|
| Multi-node coordination | Manual | Built-in |
| Parallel backup/restore | Limited | Full parallel |
| Incremental backup | Yes | Yes (better) |
| Delta restore | No | Yes |
| Backup verification | Basic | Checksums |

pgBackRest is better suited for multi-node Citus deployments.

### 4. Why etcd for Patroni (Not Consul/ZooKeeper)?

**Decision:** Use etcd as Patroni's distributed configuration store.

**Rationale:**
- Already planned for `1-monitoring-infrastructure`
- Simpler than Consul (no service mesh overhead)
- etcd 3-node cluster tolerates 1 failure
- Low latency within Nuremberg DC (<5ms)

### 5. Table Distribution Strategy

**Decision:** Distribute by `organization_id`, keep Oban local.

| Table Type | Strategy | Reason |
|------------|----------|--------|
| `organizations` | Distributed (anchor) | Distribution key source |
| `users` | Distributed by `organization_id` | Co-locate with org |
| `monitors` | Distributed by `organization_id` | Co-locate with org |
| `incidents` | Distributed by `organization_id` | Co-locate with org |
| `regions` | Reference (replicated) | Small, read-heavy |
| `plans` | Reference (replicated) | Small, read-heavy |
| `oban_jobs` | Local | Oban requires local tables |
| `oban_peers` | Local | Oban requires local tables |

**Why Oban stays local:**
- Oban uses PostgreSQL LISTEN/NOTIFY (doesn't work across shards)
- Job queue doesn't need horizontal scaling at our scale
- Oban Pro has distributed features, but open-source requires local

### 6. Coordinator Placement

**Decision:** Run coordinator on nbg-1 alongside etcd leader.

**Rationale:**
- Simplifies Patroni configuration
- etcd leader and PostgreSQL coordinator co-located
- Reduces network hops for leader election
- Can be separated later if needed

---

## Data Flow

### Write Path

```
Application
    │
    ▼
Coordinator (nbg-1)
    │
    ├─── Parse query, determine shard
    │
    ├─── organization_id % 32 = shard_id
    │
    ├─── Route to appropriate worker
    │
    ▼
┌─────────────────────────────────────┐
│  Worker 1 (even shards)             │
│  Worker 2 (odd shards)              │
└─────────────────────────────────────┘
    │
    ▼
WAL archived to B2 (each worker independently)
```

### Read Path (Distributed Query)

```
Application
    │
    ▼
Coordinator (nbg-1)
    │
    ├─── Parse query
    │
    ├─── If organization_id in WHERE:
    │    └─── Route to single worker (fast)
    │
    ├─── If no organization_id:
    │    └─── Fan out to all workers (slower)
    │
    ▼
Workers execute locally, return results
    │
    ▼
Coordinator merges results
    │
    ▼
Return to application
```

### Oban Job Flow (Local Only)

```
Application
    │
    ├─── Oban.insert(job)
    │
    ▼
Coordinator (nbg-1)
    │
    ├─── INSERT INTO oban.oban_jobs (LOCAL table)
    │
    ├─── NOTIFY oban_insert
    │
    ▼
Oban workers (same node) pick up job
```

---

## Schema Design

### Organizations Table (Distribution Anchor)

```sql
CREATE TABLE app.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    plan VARCHAR(50) DEFAULT 'free',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Distribute as the anchor table
SELECT create_distributed_table('app.organizations', 'id');
```

### Users Table (Distributed)

```sql
CREATE TABLE app.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES app.organizations(id),
    email VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    hashed_password VARCHAR(255),
    role VARCHAR(50) DEFAULT 'member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Distribute by organization_id, co-locate with organizations
SELECT create_distributed_table('app.users', 'organization_id', colocate_with => 'app.organizations');
```

### Monitors Table (Distributed)

```sql
CREATE TABLE app.monitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES app.organizations(id),
    user_id UUID NOT NULL REFERENCES app.users(id),
    name VARCHAR(255) NOT NULL,
    url TEXT NOT NULL,
    monitor_type VARCHAR(50) NOT NULL,
    interval INTEGER DEFAULT 300,
    timeout INTEGER DEFAULT 30,
    status VARCHAR(50) DEFAULT 'active',
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

SELECT create_distributed_table('app.monitors', 'organization_id', colocate_with => 'app.organizations');
```

### Reference Tables (Replicated)

```sql
CREATE TABLE app.regions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true
);

-- Replicate to all workers (small table, read-heavy)
SELECT create_reference_table('app.regions');
```

### Oban Tables (Local - NOT Distributed)

```sql
-- Oban migrations run normally
-- Tables stay on coordinator only
-- DO NOT run create_distributed_table on oban schema
```

---

## Elixir/Ecto Configuration

### Repo Configuration

```elixir
# config/config.exs
config :uptrack, Uptrack.Repo,
  adapter: Ecto.Adapters.Postgres,
  # Citus-compatible settings
  pool_size: 10,
  # Target coordinator
  hostname: "100.64.1.1",
  port: 5432,
  database: "uptrack_prod"
```

### Query Patterns

```elixir
# GOOD: Include organization_id (routes to single shard)
def get_monitor(org, id) do
  Repo.get_by(Monitor, id: id, organization_id: org.id)
end

# GOOD: Filter by organization_id
def list_monitors(org) do
  from(m in Monitor, where: m.organization_id == ^org.id)
  |> Repo.all()
end

# BAD: No organization_id (fans out to all shards)
def get_monitor_bad(id) do
  Repo.get(Monitor, id)  # Avoid this pattern
end
```

### Organization Context

```elixir
defmodule Uptrack.Organizations do
  def get_organization!(id) do
    Repo.get!(Organization, id)
  end

  def get_organization_by_slug!(slug) do
    Repo.get_by!(Organization, slug: slug)
  end

  def create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end
end
```

---

## pgBackRest Configuration

### Configuration File (Each Node)

```ini
# /etc/pgbackrest/pgbackrest.conf

[global]
# Backblaze B2 via S3-compatible API
repo1-type=s3
repo1-s3-endpoint=s3.us-west-004.backblazeb2.com
repo1-s3-bucket=uptrack-pgbackrest
repo1-s3-region=us-west-004
repo1-path=/citus-{stanza}
repo1-retention-full=2
repo1-retention-diff=7

# Performance
process-max=3
compress-type=zst
compress-level=3

# Encryption (AES-256)
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass={from-secret}

# Logging
log-level-console=info
log-level-file=detail

[{stanza}]
pg1-path=/var/lib/postgresql/17/data
pg1-port=5432
```

### Backup Schedule

| Type | Frequency | Retention | Size (est.) |
|------|-----------|-----------|-------------|
| Full | Weekly (Sunday 2am) | 2 copies | ~50GB/node |
| Differential | Daily (2am) | 7 days | ~5GB/node |
| WAL | Continuous | 7 days | ~1GB/day/node |

### NixOS Module

```nix
# /infra/nixos/modules/services/pgbackrest.nix
{ config, pkgs, lib, ... }:

let
  cfg = config.services.uptrack.pgbackrest;
in
{
  options.services.uptrack.pgbackrest = {
    enable = lib.mkEnableOption "pgBackRest backup service";
    stanza = lib.mkOption {
      type = lib.types.str;
      description = "pgBackRest stanza name";
    };
    b2Bucket = lib.mkOption {
      type = lib.types.str;
      default = "uptrack-pgbackrest";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.pgbackrest ];

    environment.etc."pgbackrest/pgbackrest.conf".text = ''
      [global]
      repo1-type=s3
      repo1-s3-endpoint=s3.us-west-004.backblazeb2.com
      repo1-s3-bucket=${cfg.b2Bucket}
      repo1-s3-region=us-west-004
      repo1-path=/citus-${cfg.stanza}
      repo1-retention-full=2
      repo1-retention-diff=7

      process-max=3
      compress-type=zst
      compress-level=3

      repo1-cipher-type=aes-256-cbc

      log-level-console=info
      log-level-file=detail

      [${cfg.stanza}]
      pg1-path=/var/lib/postgresql/17/data
      pg1-port=5432
    '';

    # PostgreSQL archive settings
    services.postgresql.settings = {
      archive_mode = "on";
      archive_command = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=${cfg.stanza} archive-push %p";
      archive_timeout = "60";
    };

    # Weekly full backup
    systemd.services.pgbackrest-full = {
      description = "pgBackRest full backup";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=${cfg.stanza} --type=full backup";
      };
    };

    systemd.timers.pgbackrest-full = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 02:00";
        Persistent = true;
      };
    };

    # Daily differential backup
    systemd.services.pgbackrest-diff = {
      description = "pgBackRest differential backup";
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --stanza=${cfg.stanza} --type=diff backup";
      };
    };

    systemd.timers.pgbackrest-diff = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Mon..Sat 02:00";
        Persistent = true;
      };
    };
  };
}
```

### B2 Bucket Structure

```
uptrack-pgbackrest/
├── citus-coordinator/
│   ├── archive/
│   │   └── 17-1/         # WAL archives
│   ├── backup/
│   │   └── 17-1/         # Base backups
│   └── backup.info       # Backup catalog
├── citus-worker1/
│   ├── archive/
│   ├── backup/
│   └── backup.info
├── citus-worker2/
│   ├── archive/
│   ├── backup/
│   └── backup.info
└── restore-points/
    └── 2025-12-03.json   # LSN mapping for coordinated restore
```

---

## Restore Procedures

### Single Node Restore

```bash
# 1. Stop PostgreSQL
systemctl stop postgresql

# 2. Clear data directory
rm -rf /var/lib/postgresql/17/data/*

# 3. Restore latest backup
pgbackrest --stanza=worker1 restore

# 4. Start PostgreSQL
systemctl start postgresql

# 5. Verify
psql -c "SELECT pg_is_in_recovery();"
```

### Point-in-Time Recovery (Single Node)

```bash
pgbackrest --stanza=coordinator \
  --type=time \
  --target="2025-12-03 14:30:00+00" \
  restore
```

### Full Cluster Restore (Coordinated PITR)

```bash
#!/bin/bash
# restore-cluster.sh

TARGET_TIME="2025-12-03 14:30:00+00"

echo "=== Stopping all PostgreSQL instances ==="
for node in nbg-1 nbg-2 nbg-3; do
  ssh root@$node "systemctl stop postgresql"
done

echo "=== Restoring coordinator ==="
ssh root@nbg-1 "
  rm -rf /var/lib/postgresql/17/data/*
  pgbackrest --stanza=coordinator --type=time --target='$TARGET_TIME' restore
"

echo "=== Restoring workers ==="
ssh root@nbg-2 "
  rm -rf /var/lib/postgresql/17/data/*
  pgbackrest --stanza=worker1 --type=time --target='$TARGET_TIME' restore
"

ssh root@nbg-3 "
  rm -rf /var/lib/postgresql/17/data/*
  pgbackrest --stanza=worker2 --type=time --target='$TARGET_TIME' restore
"

echo "=== Starting coordinator first ==="
ssh root@nbg-1 "systemctl start postgresql"
sleep 10

echo "=== Starting workers ==="
ssh root@nbg-2 "systemctl start postgresql"
ssh root@nbg-3 "systemctl start postgresql"

echo "=== Verifying cluster health ==="
ssh root@nbg-1 "psql -c \"SELECT * FROM citus_check_cluster_node_health();\""
```

---

## Patroni Configuration

### Coordinator HA (Phase 2)

```yaml
# /etc/patroni/patroni.yml (coordinator)
scope: uptrack-coordinator
name: nbg-1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 100.64.1.1:8008

etcd3:
  hosts:
    - 100.64.1.1:2379
    - 100.64.1.2:2379
    - 100.64.1.3:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      parameters:
        shared_preload_libraries: 'citus'
        citus.node_conninfo: 'sslmode=prefer'

  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 100.64.1.1:5432
  data_dir: /var/lib/postgresql/17/data
  bin_dir: /run/current-system/sw/bin

  authentication:
    replication:
      username: replicator
      password: '{from-secret}'
    superuser:
      username: postgres
      password: '{from-secret}'

  parameters:
    shared_preload_libraries: 'citus'
    archive_mode: 'on'
    archive_command: 'pgbackrest --stanza=coordinator archive-push %p'
```

---

## Migration Strategy

### From Current Schema to Citus-Ready

```elixir
defmodule Uptrack.Repo.Migrations.AddOrganizations do
  use Ecto.Migration

  def up do
    # 1. Create organizations table
    create table(:organizations, prefix: :app, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :plan, :string, default: "free"
      add :settings, :map, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:organizations, [:slug], prefix: :app)

    # 2. Add organization_id to users
    alter table(:users, prefix: :app) do
      add :organization_id, references(:organizations, type: :uuid, prefix: :app)
    end

    # 3. Add organization_id to all tenant tables
    for table <- [:monitors, :incidents, :alert_channels, :status_pages] do
      alter table(table, prefix: :app) do
        add :organization_id, references(:organizations, type: :uuid, prefix: :app)
      end
    end

    # 4. Create default organization for existing data
    execute """
    INSERT INTO app.organizations (id, name, slug, created_at, updated_at)
    VALUES (gen_random_uuid(), 'Default Organization', 'default', NOW(), NOW())
    """

    # 5. Backfill organization_id for existing data
    execute """
    UPDATE app.users SET organization_id = (SELECT id FROM app.organizations WHERE slug = 'default')
    WHERE organization_id IS NULL
    """

    for table <- [:monitors, :incidents, :alert_channels, :status_pages] do
      execute """
      UPDATE app.#{table} SET organization_id = (
        SELECT organization_id FROM app.users WHERE app.users.id = app.#{table}.user_id
      )
      WHERE organization_id IS NULL
      """
    end

    # 6. Make organization_id NOT NULL after backfill
    alter table(:users, prefix: :app) do
      modify :organization_id, :uuid, null: false
    end

    for table <- [:monitors, :incidents, :alert_channels, :status_pages] do
      alter table(table, prefix: :app) do
        modify :organization_id, :uuid, null: false
      end
    end

    # 7. Distribute tables (only on Citus cluster)
    # These will be no-ops on standard PostgreSQL
    execute "SELECT create_distributed_table('app.organizations', 'id')"
    execute "SELECT create_distributed_table('app.users', 'organization_id', colocate_with => 'app.organizations')"
    execute "SELECT create_distributed_table('app.monitors', 'organization_id', colocate_with => 'app.organizations')"
    execute "SELECT create_distributed_table('app.incidents', 'organization_id', colocate_with => 'app.organizations')"
    execute "SELECT create_distributed_table('app.alert_channels', 'organization_id', colocate_with => 'app.organizations')"
    execute "SELECT create_distributed_table('app.status_pages', 'organization_id', colocate_with => 'app.organizations')"

    # 8. Create reference tables
    execute "SELECT create_reference_table('app.regions')"
  end

  def down do
    # ... reverse migrations
  end
end
```

---

## Capacity Planning

### Write Capacity

| Scale | Monitors | Writes/sec | Citus Needed? |
|-------|----------|------------|---------------|
| Current | 10,000 | 222 | No (single node OK) |
| 3x | 30,000 | 666 | No |
| 10x | 100,000 | 2,222 | Beneficial |
| 30x | 300,000 | 6,666 | Yes |

**Citus benefits appear at ~100K monitors, required at ~300K.**

### Storage per Worker

```
Per worker (32 shards each):
- 10K monitors: ~25GB
- 100K monitors: ~250GB
- 500K monitors: ~1.25TB

Netcup G12 (512GB NVMe): Supports up to ~200K monitors per worker
```

### Connection Pooling

```
Coordinator connections:
- Application pool: 50
- Citus inter-node: 32 (per worker)
- Replication: 5
- Admin: 5
Total: ~100 connections

Worker connections:
- From coordinator: 32
- Local maintenance: 10
Total: ~50 connections per worker
```

---

## Monitoring

### Key Metrics

```sql
-- Citus cluster health
SELECT * FROM citus_check_cluster_node_health();

-- Shard distribution
SELECT nodename, count(*) as shards
FROM citus_shards
GROUP BY nodename;

-- Query distribution
SELECT * FROM citus_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Replication lag (if using streaming replica)
SELECT client_addr, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes
FROM pg_stat_replication;
```

### Prometheus Metrics

```yaml
# postgres_exporter queries for Citus
pg_citus_worker_count:
  query: "SELECT count(*) FROM pg_dist_node WHERE isactive"
  metrics:
    - count:
        usage: "GAUGE"
        description: "Number of active Citus workers"

pg_citus_shard_count:
  query: "SELECT count(*) FROM citus_shards"
  metrics:
    - count:
        usage: "GAUGE"
        description: "Total number of shards"
```

---

## Security

### Network Security (Tailscale)

```
All PostgreSQL communication over Tailscale:
- Coordinator ↔ Workers: 100.64.1.x (encrypted)
- Application → Coordinator: 100.64.1.1:5432 (encrypted)
- No public PostgreSQL exposure
```

### Authentication

```
- Superuser: postgres (local socket only)
- Application: uptrack_app (scram-sha-256)
- Replication: replicator (scram-sha-256)
- Citus inter-node: citus (scram-sha-256)
```

### Backup Encryption

```
pgBackRest:
- repo1-cipher-type=aes-256-cbc
- Encryption key stored in sops-nix/agenix
- All backups encrypted at rest in B2
```

---

## Cost Summary

| Component | Monthly Cost |
|-----------|--------------|
| Netcup G12 Pro × 3 (existing) | €21 |
| Backblaze B2 storage (~500GB) | ~$3 |
| Backblaze B2 egress (restore) | ~$0 (rare) |
| **Total** | **~€24/mo** |

No additional infrastructure cost vs standard PostgreSQL - Citus is free open-source extension.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Coordinator failure | Medium | High | Patroni auto-failover (Phase 2) |
| Worker failure | Low | Medium | Restore from pgBackRest |
| Backup corruption | Low | Critical | Checksums + 2 full copies |
| Network partition | Low | High | etcd quorum (3 nodes) |
| Citus upgrade issues | Low | Medium | Test upgrades on staging |

---

## Open Questions

1. **Coordinator HA timeline** - When to add coordinator standby (4th node)?
2. **Connection pooling** - PgBouncer needed, or Ecto pool sufficient?
3. **Read replicas** - Add India read replica for Asia latency?
4. **Citus version** - Pin to specific version or track latest?
