# Archived Documentation (Pre-OpenSpec)

**Date**: 2025-10-30
**Reason**: Superseded by OpenSpec structured proposals

---

## What's Here

This archive contains architecture documentation created before adopting OpenSpec.

### Files

- **region_check_worker.md** - Early worker design and NATS vs Oban analysis
  - *Superseded by*: `/openspec/changes/add-regional-monitoring-workers/`

- **scale-plan.md** - VictoriaMetrics cluster scaling strategies
  - *Superseded by*: `/openspec/changes/establish-multi-region-monitoring-infrastructure/specs/metrics-storage/`

- **oracle-netcup-ovh-architecture.md** - 3-node provider comparison
  - *Superseded by*: `/openspec/changes/establish-multi-region-monitoring-infrastructure/design.md`

- **final-5-node-architecture.md** - Initial 5-node architecture design
  - *Superseded by*: `/openspec/changes/establish-multi-region-monitoring-infrastructure/proposal.md`

---

## Why Archived?

OpenSpec provides structured requirements with:
- ✅ Validation tooling (catches incomplete specs)
- ✅ Scenario-based testing (Given/When/Then)
- ✅ Task tracking integration
- ✅ Cross-referencing between related changes
- ✅ Version control of architecture decisions

These markdown docs were valuable for exploration but lacked the rigor needed for production deployment.

---

## Historical Value

These docs capture the **thought process** that led to current OpenSpec proposals:
- Analyzed NATS vs Oban trade-offs → Chose Oban
- Evaluated 2-cluster vs single-cluster VictoriaMetrics → Chose 3-node single cluster
- Compared provider pricing → Chose Netcup for EU, Oracle Free for Asia
- Debated ClickHouse vs VictoriaMetrics → Chose VictoriaMetrics

**If you're curious why we made certain decisions, read these first, then see the formal decision in OpenSpec design.md files.**

---

## Migration Timeline

| Date | Action |
|------|--------|
| 2025-10-19 | Created `final-5-node-architecture.md` (last markdown design doc) |
| 2025-10-30 | Created OpenSpec proposals (`establish-multi-region-monitoring-infrastructure`, `add-regional-monitoring-workers`) |
| 2025-10-30 | Archived all pre-OpenSpec architecture docs to this directory |

---

**For current architecture, see**: `/openspec/changes/` and `/docs/architecture/README.md`
