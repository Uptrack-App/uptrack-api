# Uptrack Architecture Documentation

This directory contains architecture-related documentation for Uptrack's infrastructure and design decisions.

---

## 📚 Primary Documentation (OpenSpec)

**All new architecture is documented in OpenSpec proposals** at `/openspec/changes/`

### Active OpenSpec Proposals

**[establish-multi-region-monitoring-infrastructure](../../openspec/changes/establish-multi-region-monitoring-infrastructure/)** ⭐
- **Purpose**: 5-node infrastructure with PostgreSQL HA, VictoriaMetrics cluster, and Tailscale networking
- **Status**: Validated, ready to apply
- **Key docs**:
  - `proposal.md` - Why and what (high-level overview)
  - `design.md` - Architecture decisions and trade-offs
  - `tasks.md` - 124 implementation tasks across 8 phases
  - `specs/` - 21 requirements across 6 capabilities

**[add-regional-monitoring-workers](../../openspec/changes/add-regional-monitoring-workers/)** ⭐
- **Purpose**: Distributed Oban workers for multi-region monitoring checks
- **Status**: Validated, ready to apply
- **Depends on**: `establish-multi-region-monitoring-infrastructure`
- **Key docs**:
  - `proposal.md` - Why and what (worker architecture)
  - `design.md` - 6 key design decisions, data flow, scaling strategy
  - `tasks.md` - 60+ tasks across 8 phases
  - `specs/` - 14 requirements across 3 capabilities

### How to Use OpenSpec Proposals

```bash
# View proposal summary
cat openspec/changes/establish-multi-region-monitoring-infrastructure/proposal.md

# List all changes
openspec list

# Start implementing a change
/openspec:apply establish-multi-region-monitoring-infrastructure

# Validate a proposal
openspec validate add-regional-monitoring-workers --strict
```

---

## 📖 Legacy Documentation (Archived)

**Historical docs moved to** `/docs/archive/2025-10-30-pre-openspec/`

These docs capture the thought process that led to the current OpenSpec proposals:
- `region_check_worker.md` - Early worker design (superseded by workers OpenSpec)
- `scale-plan.md` - VictoriaMetrics scaling ideas (now in infrastructure OpenSpec)
- `oracle-netcup-ovh-architecture.md` - Provider comparison (now in infrastructure design.md)
- `final-5-node-architecture.md` - Initial 5-node design (now in infrastructure proposal)

**Why archived?** OpenSpec provides:
- ✅ Structured requirements with scenarios (Given/When/Then)
- ✅ Validation tooling (ensures completeness)
- ✅ Implementation task tracking
- ✅ Version control of architecture changes
- ✅ Cross-referencing between related changes

---

## 🎯 Current Architecture (2025-10-30)

### Infrastructure Status

| Component | Status | OpenSpec Change |
|-----------|--------|-----------------|
| **5-node deployment** | Proposed | `establish-multi-region-monitoring-infrastructure` |
| **PostgreSQL HA (Patroni + etcd)** | Proposed | Same as above |
| **VictoriaMetrics cluster** | Proposed | Same as above |
| **Tailscale mesh network** | Proposed | Same as above |
| **WAL-G backups to B2** | Proposed | Same as above |
| **Regional workers** | Proposed | `add-regional-monitoring-workers` |
| **NixOS profiles** | Proposed | `add-regional-monitoring-workers` |

### Planned Deployment

```
eu-a (Italy/Austria, Netcup) - PostgreSQL + VictoriaMetrics + Worker
eu-b (Italy/Austria, Netcup) - PostgreSQL + VictoriaMetrics + Worker
eu-c (Italy/Austria, Netcup) - PostgreSQL + VictoriaMetrics + Worker
india-s (Oracle Free) - PostgreSQL replica + Worker
india-w (Oracle Free) - Worker + etcd

Total Cost: ~$23/month (initially Hostkey €15.69, migrate to Netcup €20.34)
```

### Key Features
- ✅ PostgreSQL 17 with automatic failover (<30s RTO)
- ✅ VictoriaMetrics cluster (3 vmstorage, 2 vminsert, 3 vmselect)
- ✅ 15-month metrics retention (~35GB storage)
- ✅ Supports 10K monitors (666 samples/sec)
- ✅ 5-node etcd cluster (tolerates 2 failures)
- ✅ Regional workers (EU + Asia initially, expandable)
- ✅ Zero-downtime provider migration (Hostkey → Netcup)

---

## 🗺️ Getting Started

### For New Team Members
1. Read `openspec/changes/establish-multi-region-monitoring-infrastructure/proposal.md` - Get the big picture
2. Review `design.md` in same directory - Understand key decisions
3. Scan `tasks.md` - See implementation roadmap

### For Operations (Deployment)
1. Follow `/openspec:apply establish-multi-region-monitoring-infrastructure` workflow
2. Check task completion in `tasks.md`
3. Refer to `specs/` for requirement details and scenarios

### For Architecture Changes
1. Review existing OpenSpec changes: `openspec list --specs`
2. Create new proposal: `/openspec:proposal <change-id>`
3. Follow OpenSpec conventions in `/openspec/AGENTS.md`

---

## 🤔 Common Questions

### Why OpenSpec instead of markdown docs?
**Answer**: OpenSpec provides structured requirements with validation, task tracking, and ensures proposals are complete before implementation. Plain markdown docs often miss edge cases and become outdated.

### Where's the old architecture documentation?
**Answer**: Moved to `/docs/archive/2025-10-30-pre-openspec/`. OpenSpec proposals supersede these docs with more rigorous specifications.

### Why VictoriaMetrics instead of ClickHouse?
**Answer**: See `establish-multi-region-monitoring-infrastructure/design.md` → "Key Design Decision #4: Why VictoriaMetrics"

### How do we scale to 20K monitors?
**Answer**: See `establish-multi-region-monitoring-infrastructure/design.md` → "Capacity Planning" section

### How much does adding a region cost?
**Answer**: See `add-regional-monitoring-workers/design.md` → "Cost Analysis" section
- Phase 1 (co-located): $0
- Phase 2 (dedicated worker): +$2.50/month per region

### What's the deployment timeline?
**Answer**:
- Infrastructure: 2-3 weeks (Phase 1-8 in infrastructure tasks.md)
- Workers: 5-8 days (depends on infrastructure being deployed)

---

## 📋 Related Documentation

### OpenSpec
- `/openspec/AGENTS.md` - How to create and apply proposals
- `/openspec/project.md` - Project-wide context for AI assistants

### Deployment
- `/docs/deployment/` - Deployment guides and runbooks
- `/CLAUDE.md` - NixOS deployment best practices

### Operations
- `/docs/oban/` - Oban worker configuration and scaling
- `/docs/db/` - Database setup guides

---

## 🔍 Quick Links

### Architecture Decisions
- [Why Tailscale mesh network?](../../openspec/changes/establish-multi-region-monitoring-infrastructure/design.md#1-why-tailscale-over-public-ips)
- [Why etcd only in EU?](../../openspec/changes/establish-multi-region-monitoring-infrastructure/design.md#2-why-etcd-only-in-eu-not-india)
- [Why Oban instead of NATS?](../../openspec/changes/add-regional-monitoring-workers/design.md#1-why-oban-not-nats-not-custom-queue)
- [Why NixOS profiles?](../../openspec/changes/add-regional-monitoring-workers/design.md#2-why-nixos-profiles-not-per-node-configs)

### Cost & Capacity
- [Infrastructure costs](../../openspec/changes/establish-multi-region-monitoring-infrastructure/design.md#cost-analysis)
- [Worker costs per region](../../openspec/changes/add-regional-monitoring-workers/design.md#migration-path)
- [Storage capacity planning](../../openspec/changes/establish-multi-region-monitoring-infrastructure/specs/metrics-storage/spec.md)

### Technical Specs
- [PostgreSQL HA requirements](../../openspec/changes/establish-multi-region-monitoring-infrastructure/specs/database-ha/spec.md)
- [VictoriaMetrics cluster](../../openspec/changes/establish-multi-region-monitoring-infrastructure/specs/metrics-storage/spec.md)
- [Worker resource limits](../../openspec/changes/add-regional-monitoring-workers/specs/workers/spec.md)

---

**Last Updated**: 2025-10-30
**Maintained by**: Infrastructure Team
**Documentation Format**: OpenSpec (structured proposals with validation)
