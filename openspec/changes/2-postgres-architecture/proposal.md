# Proposal: PostgreSQL Architecture with Citus + Patroni

**Status**: Draft
**Created**: 2025-12-03
**Depends on**: `1-monitoring-infrastructure` (Tailscale networking)

---

## Why

Uptrack needs a PostgreSQL architecture that:
1. **Scales writes horizontally** - Support 300K+ monitors without architectural changes
2. **Provides automatic failover** - <30 second RTO for node failures
3. **Enables multi-tenancy** - Clean data isolation via `organization_id` sharding
4. **Supports disaster recovery** - Point-in-time recovery with pgBackRest + Backblaze B2

**Current state:**
- Schema uses `user_id` as foreign key (not Citus-ready)
- No `organizations` table for multi-tenant sharding
- No backup infrastructure defined

**Problems with retrofitting Citus later:**
- Adding `organization_id` to all tables requires data migration
- Cross-shard foreign key constraints need redesign
- Query patterns must change to include distribution key
- Significant downtime for schema changes

**Decision:** Start with Citus from day one to avoid painful migration.

---

## What Changes

### Core Architecture

**Citus Distributed Cluster (3 Netcup nodes):**
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

**Each node has its own WAL stream** - backup ALL nodes with pgBackRest.

### Components

1. **Citus Extension** - Horizontal sharding by `organization_id`
2. **Patroni** - Automatic failover for coordinator HA
3. **etcd** - Consensus store for Patroni leader election
4. **pgBackRest** - Backups to Backblaze B2 with PITR
5. **NixOS** - Declarative configuration for all components

### Schema Changes

- **ADD** `organizations` table as distribution anchor
- **ADD** `organization_id` to all tenant tables (users, monitors, incidents, etc.)
- **KEEP** Oban tables local (not distributed)
- **KEEP** Reference tables replicated (regions, plans, etc.)

### Table Distribution Strategy

| Table Type | Distribution | Example |
|------------|--------------|---------|
| Tenant data | `organization_id` | monitors, incidents, users |
| Reference data | Replicated | regions, plans, check_types |
| System data | Local | oban_jobs, oban_peers |

---

## Impact

### Affected Specs
- `database-ha` - New capability for PostgreSQL HA architecture

### Affected Code
- `priv/app_repo/migrations/` - New migration for organizations + organization_id
- `lib/uptrack/accounts/` - Organization context
- `lib/uptrack/monitoring/` - Add organization_id to queries
- `config/runtime.exs` - Citus-aware Ecto configuration

### Dependencies
- **Prerequisite**: `1-monitoring-infrastructure` (Tailscale mesh for secure communication)
- **NixOS packages**: `postgresql_17`, `citus`, `patroni`, `etcd`, `pgbackrest`
- **External**: Backblaze B2 bucket for backups

---

## Success Criteria

- [ ] Citus cluster running on 3 Netcup nodes (coordinator + 2 workers)
- [ ] Patroni providing automatic coordinator failover (<30s RTO)
- [ ] All tenant tables distributed by `organization_id`
- [ ] Oban tables remain local, functioning correctly
- [ ] pgBackRest backing up all nodes to B2 with encryption
- [ ] PITR restore tested and documented
- [ ] Schema migration path documented for existing data

---

## Out of Scope

- Vienna geo-replica (Phase 2 of `1-monitoring-infrastructure`)
- Citus Enterprise features (use open-source Citus)
- Read replicas in India (future enhancement)
- Connection pooling with PgBouncer (evaluate if needed)

---

## Cost Analysis

| Component | Quantity | Monthly Cost |
|-----------|----------|--------------|
| Netcup G12 Pro (existing) | 3 | €21 |
| Backblaze B2 (~500GB) | 1 | ~$3 |
| **Total** | | **~€24/mo** |

No additional infrastructure cost - uses existing Netcup nodes from `1-monitoring-infrastructure`.

---

## Related

- Infrastructure: `1-monitoring-infrastructure` (prerequisite)
- Backup docs: `/docs/infrastructure/pgbackrest-setup.md` (to be created)
- NixOS modules: `/infra/nixos/modules/services/` (postgresql, patroni, pgbackrest)
