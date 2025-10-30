# Proposal: Add Regional Monitoring Workers

**Status**: Draft
**Created**: 2025-10-30
**Depends on**: `establish-multi-region-monitoring-infrastructure`

---

## Why

Uptrack needs distributed monitoring workers to perform checks from multiple geographic regions, providing accurate latency measurements and detecting region-specific outages.

**Current state:**
- Infrastructure proposal defines 5 nodes (eu-a/b/c, india-s, india-w) but no worker implementation
- Monitoring code exists (`CheckWorker`, `ObanCheckWorker`) but not deployed regionally
- No NixOS profiles for worker vs infrastructure node roles

**Problems to solve:**
1. **No regional check execution**: All checks would run from a single location, defeating multi-region monitoring
2. **Unclear NixOS structure**: Current node configs mix infrastructure services (PostgreSQL, VictoriaMetrics) with application concerns
3. **Hard to scale**: Adding a new region (Tokyo, Singapore) requires duplicating entire node config
4. **Resource inefficiency**: Can't deploy lightweight worker-only nodes ($2.50/month) without full infrastructure stack

**Business impact:**
- Users expect checks from their selected regions (EU, Asia, Americas)
- Competitive disadvantage vs UptimeRobot (10+ regions), Pingdom (70+ locations)
- Current architecture supports 10K monitors but zero regional distribution

---

## What

Implement Oban-based regional monitoring workers with profile-driven NixOS configuration for easy expansion.

### Core Components

1. **Regional Worker Application**
   - Minimal Elixir application running Oban workers
   - Connects to central PostgreSQL (Germany) via Tailscale
   - Processes regional queues (`checks_eu`, `checks_asia`, `checks_americas`)
   - Writes results to VictoriaMetrics (Austria)
   - Memory footprint: ~280MB (fits in 512MB VPS)

2. **NixOS Profile Architecture**
   ```
   common/
     base.nix          # All nodes (SSH, Tailscale, monitoring)
   profiles/
     infrastructure.nix  # Full stack (DB, VM, etcd)
     worker.nix          # Workers only (Oban, checks)
   regions/
     europe/
       eu-a/           # Imports: base + infrastructure + worker
       eu-b/           # Imports: base + infrastructure + worker
     asia/
       india-s/        # Imports: base + infrastructure + worker
       tokyo/          # Imports: base + worker (future)
   ```

3. **Regional Queue Routing**
   - Central scheduler (any node) inserts jobs to regional queues
   - Workers subscribe to their region's queue only
   - Queue naming: `checks_{region}` where region = eu|asia|americas|etc

4. **Scaling Strategy**
   - **Phase 1**: Co-locate workers on 5 infrastructure nodes (eu-a/b/c, india-s/w)
   - **Phase 2**: Add worker-only nodes for new regions (Tokyo, Singapore, São Paulo)
   - **Phase 3**: Scale workers independently of infrastructure (add more Asia workers without new databases)

### Out of Scope

- ❌ Multi-language workers (Rust, Go) - Elixir only
- ❌ Custom check types beyond HTTP/TCP/ping/keyword
- ❌ Worker-to-worker communication (all workers independent)
- ❌ Local result caching (always write to VictoriaMetrics)

### Success Criteria

- ✅ 5 workers running on infrastructure nodes (eu-a/b/c, india-s/w)
- ✅ Each worker processes checks from its region
- ✅ Adding Tokyo worker takes <30 minutes (new NixOS config + deploy)
- ✅ Worker-only node uses <300MB RAM, costs <$3/month
- ✅ All checks complete within region-appropriate timeout (EU: 5s, cross-region: 15s)
- ✅ Zero interference between worker and infrastructure services (separate systemd units, resource limits)

### Dependencies

- **Prerequisite**: `establish-multi-region-monitoring-infrastructure` must be deployed
  - Requires: PostgreSQL (Germany), VictoriaMetrics (Austria), Tailscale mesh
- **Application code**: `CheckWorker` and `ObanCheckWorker` already exist in codebase
- **NixOS refactor**: Requires restructuring `/infra/nixos/` to use profiles

### Estimated Effort

- NixOS profile refactor: 2-3 days
- Worker application deployment: 1-2 days
- Regional queue configuration: 1 day
- Testing and validation: 1-2 days
- **Total**: 5-8 days

---

## Related

- Infrastructure: `establish-multi-region-monitoring-infrastructure` (prerequisite)
- Application: `/lib/uptrack/monitoring/check_worker.ex` (existing code)
- Documentation: `/docs/architecture/region_check_worker.md` (design rationale)
