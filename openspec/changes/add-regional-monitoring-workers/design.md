# Design: Regional Monitoring Workers

**Change ID**: `add-regional-monitoring-workers`
**Date**: 2025-10-30

---

## Overview

This document captures the architectural decisions for implementing regional monitoring workers in Uptrack.

**Key principle**: Separate infrastructure concerns (databases, message queues) from application concerns (workers, checks) to enable independent scaling and deployment.

---

## Architecture Diagram

### Current Infrastructure (from prerequisite change)

```
┌─────────────────────────────────────────────────────┐
│ Infrastructure Layer (5 nodes)                       │
│                                                      │
│  eu-a (Italy/Austria)                               │
│  ├─ PostgreSQL (primary or replica)                 │
│  ├─ VictoriaMetrics (vmstorage/vminsert/vmselect)   │
│  ├─ etcd                                            │
│  └─ Tailscale (100.64.1.1)                          │
│                                                      │
│  eu-b, eu-c (similar)                               │
│  india-s, india-w (similar)                         │
└─────────────────────────────────────────────────────┘
```

### Proposed Worker Layer

```
┌─────────────────────────────────────────────────────┐
│ Application Layer (workers)                          │
│                                                      │
│  Phase 1: Co-located on infrastructure nodes        │
│  ┌──────────────────────────────────┐               │
│  │ eu-a, eu-b, eu-c                 │               │
│  │ ├─ Uptrack Worker App (systemd)  │               │
│  │ ├─ Oban: queue=checks_eu         │               │
│  │ └─ Performs HTTP/TCP/ping checks │               │
│  └──────────────────────────────────┘               │
│                                                      │
│  ┌──────────────────────────────────┐               │
│  │ india-s, india-w                 │               │
│  │ ├─ Uptrack Worker App (systemd)  │               │
│  │ ├─ Oban: queue=checks_asia       │               │
│  │ └─ Performs HTTP/TCP/ping checks │               │
│  └──────────────────────────────────┘               │
│                                                      │
│  Phase 2: Dedicated worker-only nodes (future)      │
│  ┌──────────────────────────────────┐               │
│  │ tokyo (new $2.50/mo node)        │               │
│  │ ├─ Uptrack Worker App            │               │
│  │ ├─ Oban: queue=checks_asia       │               │
│  │ ├─ NO databases, NO etcd         │               │
│  │ └─ Connects to Germany PG via TS │               │
│  └──────────────────────────────────┘               │
└─────────────────────────────────────────────────────┘
```

### Data Flow

```
User creates monitor → Central DB (Germany)
                              ↓
            Scheduler inserts jobs to regional queues
            (checks_eu, checks_asia, checks_americas)
                              ↓
        ┌────────────┬────────────┬────────────┐
        ↓            ↓            ↓            ↓
     EU worker   Asia worker  Americas      (future)
     (eu-a)      (india-s)    worker        regions
        │            │            │
        └────────────┴────────────┴──────→ VictoriaMetrics (Austria)
                                            (stores results)
```

---

## Key Design Decisions

### 1. Why Oban (not NATS, not custom queue)?

**Decision**: Use Oban with regional queues

**Rationale**:
- ✅ Already using Oban in application
- ✅ PostgreSQL already deployed (no new infrastructure)
- ✅ Oban provides retries, dead-letter queue, observability (Oban Web UI)
- ✅ Regional routing via queue names is simple: `queue: "checks_#{region}"`
- ✅ Workers connect via Tailscale (~150ms EU-India latency is acceptable for polling)
- ✅ Production-ready features built-in (job history, telemetry, cron scheduling)

**Rejected alternatives**:
- ❌ NATS: Saves 60MB RAM but adds infrastructure complexity, requires custom retry logic
- ❌ Custom queue: Reinventing Oban, high maintenance burden
- ❌ Direct API calls: No retry, no persistence, no observability

**Trade-offs**:
- Remote PostgreSQL latency (150ms EU-India) acceptable because workers poll every 1-5 seconds
- Oban uses ~130MB more RAM than NATS but provides much better developer experience

### 2. Why NixOS Profiles (not per-node configs)?

**Decision**: Restructure NixOS configs to use composable profiles

**Current structure** (problematic):
```
regions/
  europe/eu-a/default.nix       # 200 lines, mixes infrastructure + app
  europe/eu-b/default.nix       # 200 lines, almost identical to eu-a
  asia/india-s/default.nix      # 200 lines, duplicates config
```

**Proposed structure**:
```
common/
  base.nix                      # SSH, Tailscale, monitoring (50 lines)
profiles/
  infrastructure.nix            # PostgreSQL, VM, etcd (100 lines)
  worker.nix                    # Oban workers, CheckWorker (50 lines)
  minimal.nix                   # Minimal system (existing, 20 lines)
regions/
  europe/
    eu-a/default.nix            # imports = [base, infrastructure, worker] (10 lines)
    eu-b/default.nix            # imports = [base, infrastructure, worker] (10 lines)
  asia/
    india-s/default.nix         # imports = [base, infrastructure, worker] (10 lines)
    tokyo/default.nix           # imports = [base, worker] (10 lines) ← FUTURE
```

**Rationale**:
- ✅ Adding Tokyo worker: 10-line config file + 1 deploy command
- ✅ DRY: Infrastructure logic defined once in `profiles/infrastructure.nix`
- ✅ Flexibility: Can deploy worker-only nodes without full stack
- ✅ Testing: Can test profiles independently (`nixos-rebuild build --flake '.#worker-only'`)

**Migration path**:
1. Extract common logic to `common/base.nix` (already exists, needs refinement)
2. Create `profiles/infrastructure.nix` (PostgreSQL, VM, etcd config)
3. Create `profiles/worker.nix` (Uptrack app, Oban workers)
4. Refactor existing node configs to import profiles
5. Validate all nodes rebuild identically

### 3. Why Co-locate Workers on Infrastructure Nodes (Phase 1)?

**Decision**: Deploy workers on existing infrastructure nodes (eu-a/b/c, india-s/w)

**Rationale**:
- ✅ Zero new infrastructure costs
- ✅ Faster deployment (no new VPS provisioning)
- ✅ Infrastructure nodes have spare capacity (eu-a: 8GB RAM, ~4GB used, 4GB free)
- ✅ Validates worker implementation before scaling to dedicated nodes

**Resource allocation per node**:
```
eu-a (8GB RAM total):
├─ PostgreSQL:        2GB
├─ VictoriaMetrics:   1.5GB
├─ etcd:              200MB
├─ Uptrack Worker:    300MB  ← NEW
├─ System:            1GB
└─ Free:              3GB (headroom)
```

**When to add dedicated worker nodes**:
- Need coverage in regions without infrastructure (Tokyo, Singapore, São Paulo)
- Existing nodes approach resource limits (>85% RAM usage)
- Latency requirements demand local presence (<50ms checks)

### 4. How Do Workers Connect to Central Database?

**Decision**: Workers connect to PostgreSQL (Germany) via Tailscale

**Connection details**:
- Protocol: PostgreSQL wire protocol over Tailscale encrypted tunnel
- Endpoint: `100.64.1.1:5432` (eu-a's Tailscale IP, PostgreSQL primary)
- Latency: EU-EU ~20ms, EU-India ~150ms
- Connection pooling: 5-10 connections per worker (Ecto pool)

**Why acceptable**:
- Oban workers poll every 1-5 seconds (not latency-sensitive)
- Job acknowledgment (acking) after completion is async
- Oban batches acknowledgments (reduces round trips)
- Tailscale provides encryption + reliability

**Rejected alternatives**:
- ❌ Replicate Oban queue database per region: Inconsistent job distribution, complex sync
- ❌ Use message broker (NATS): Adds infrastructure, loses Oban benefits

### 5. How Are Jobs Routed to Regional Workers?

**Decision**: Queue-based routing with region-specific queues

**Scheduler behavior** (runs on any node):
```elixir
# User creates monitor with regions: ["eu", "asia"]
def schedule_check(monitor) do
  for region <- monitor.regions do
    %{monitor_id: monitor.id, url: monitor.url}
    |> Uptrack.Monitoring.ObanCheckWorker.new(queue: "checks_#{region}")
    |> Oban.insert()
  end
end
```

**Worker configuration** (per region):
```elixir
# EU worker (eu-a, eu-b, eu-c)
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  queues: [
    checks_eu: 10,      # Process EU checks
    checks_asia: 0,     # Ignore Asia checks
    checks_americas: 0  # Ignore Americas checks
  ]

# Asia worker (india-s, india-w)
config :uptrack, Oban,
  repo: Uptrack.ObanRepo,
  queues: [
    checks_eu: 0,       # Ignore EU checks
    checks_asia: 10,    # Process Asia checks
    checks_americas: 0  # Ignore Americas checks
  ]
```

**Queue naming convention**:
- Format: `checks_{region_code}`
- Region codes: `eu`, `asia`, `americas`, `oceania`, `africa`, `middle_east`
- Matches monitor region selection in UI

**Advantages**:
- ✅ Simple: Workers subscribe to queues they care about
- ✅ Flexible: Can have multiple workers per region (load distribution)
- ✅ Observable: Oban Web UI shows queue depth per region
- ✅ Resilient: If Asia workers are down, jobs stay in queue (no data loss)

### 6. What Resources Does a Worker Need?

**Minimal worker requirements**:

| Resource | Requirement | Notes |
|----------|-------------|-------|
| **RAM** | 280MB | BEAM VM (50MB) + Ecto (30MB) + Oban (30MB) + Finch (15MB) + working memory (155MB) |
| **CPU** | 0.5 vCPU | Idle most of the time, bursts during checks |
| **Disk** | 10GB | Nix store (8GB) + logs (2GB) |
| **Network** | 10 Mbps | Checks are small (few KB per request) |

**Recommended VPS** (for dedicated worker nodes):
- **Vultr High Frequency Compute**: 1 vCPU, 512MB RAM, 10GB SSD, $2.50/month
- **Hetzner CX11**: 1 vCPU, 2GB RAM, 20GB SSD, €3.79/month (~$4/month)
- **Oracle Free Tier**: 1 vCPU, 1GB RAM, 50GB, $0/month (if available)

**Co-located on infrastructure nodes**:
- Uses 300MB of available 4GB free RAM
- Negligible CPU impact (<5% average)
- Shares Nix store with other services

---

## Security Considerations

### 1. Worker Isolation

**Problem**: Workers run untrusted HTTP checks (user-supplied URLs)

**Mitigations**:
- ✅ Timeout enforcement: 30s max per check (prevents resource exhaustion)
- ✅ Systemd resource limits: `MemoryMax=400M`, `CPUQuota=50%` (prevents resource starvation)
- ✅ Network isolation: Firewall rules prevent workers accessing internal services
- ✅ User-Agent identification: `Uptrack Monitor/1.0` (websites can block if needed)

### 2. Database Access

**Problem**: Workers need PostgreSQL access but shouldn't access all data

**Mitigations**:
- ✅ Read-only user: Workers use `uptrack_worker` role (SELECT only on monitors, INSERT only on check_results)
- ✅ Row-level security: Workers can only see monitors assigned to their region
- ✅ Tailscale authentication: Only Tailscale nodes can connect to PostgreSQL

### 3. Result Integrity

**Problem**: Malicious worker could forge check results

**Mitigations**:
- ✅ Worker authentication: Workers authenticate via database user credentials
- ✅ Node identity: Results tagged with `node_name` (audit trail)
- ✅ Anomaly detection: Alert if results differ significantly across regions

---

## Operational Considerations

### 1. Deployment

**Deploying workers to existing infrastructure nodes**:
```bash
# Build worker profile
nixos-rebuild build --flake '.#eu-a' --max-jobs 3

# Deploy to eu-a
nixos-rebuild switch --flake '.#eu-a' --target-host eu-a --use-remote-sudo

# Verify worker started
ssh eu-a systemctl status uptrack-worker
ssh eu-a journalctl -u uptrack-worker -f
```

**Adding new worker-only node (Tokyo example)**:
```bash
# 1. Provision VPS, install NixOS
# 2. Create config: regions/asia/tokyo/default.nix (10 lines)
# 3. Deploy
nixos-rebuild switch --flake '.#tokyo' --target-host tokyo

# 4. Verify
ssh tokyo systemctl status uptrack-worker
```

### 2. Monitoring

**Worker health metrics**:
- Oban queue depth per region (via Oban Web UI or Prometheus)
- Check completion rate per region
- Worker CPU/RAM usage (via node_exporter)
- Failed checks per region (via Alertmanager)

**Alerts**:
- `WorkerDown`: Worker hasn't processed jobs in 5 minutes
- `HighQueueDepth`: Queue depth >1000 for 10 minutes (backlog)
- `HighFailureRate`: >50% checks failing in region for 5 minutes

### 3. Scaling

**Horizontal scaling** (add more workers):
```
# EU has 3 workers (eu-a, eu-b, eu-c)
# All process checks_eu queue
# Oban distributes jobs across workers automatically (SKIP LOCKED)

# If EU checks take too long:
# Option 1: Add worker-only EU node (Berlin, London)
# Option 2: Increase concurrency on existing workers
config :uptrack, Oban, queues: [checks_eu: 20]  # Was 10
```

**Vertical scaling** (faster checks):
- Increase worker CPU/RAM (allows higher concurrency)
- Optimize CheckWorker (faster HTTP client, connection pooling)

### 4. Disaster Recovery

**Scenario: All EU workers down**
- Checks queue in PostgreSQL (no data loss)
- Asia workers unaffected (still process checks_asia)
- When EU workers recover, process backlog (FIFO order)

**Scenario: PostgreSQL primary (Germany) down**
- Patroni promotes Austria to primary (<30s)
- Workers reconnect automatically (Ecto handles reconnection)
- Jobs in-flight may fail (Oban retries automatically)

---

## Testing Strategy

### 1. Unit Tests

- `CheckWorker`: HTTP/TCP/ping/keyword checks
- `ObanCheckWorker`: Job processing, error handling
- `MonitorScheduler`: Queue routing logic

### 2. Integration Tests

- Worker connects to PostgreSQL via Tailscale
- Worker pulls jobs from correct regional queue
- Worker writes results to VictoriaMetrics
- Worker respects resource limits (MemoryMax, CPUQuota)

### 3. Load Tests

- 100 workers × 10 concurrent checks = 1000 checks/sec
- Verify PostgreSQL connection pool doesn't exhaust
- Verify VictoriaMetrics ingestion rate handles load
- Measure end-to-end latency (job insert → check complete → result written)

---

## Alternatives Considered

### Alternative 1: Worker-per-Monitor Model

**Description**: Each monitor gets dedicated worker process

**Rejected because**:
- ❌ 10K monitors = 10K processes (resource intensive)
- ❌ Process startup/shutdown overhead
- ❌ Complex scheduling (Oban provides this for free)

### Alternative 2: Centralized Workers (No Regional Distribution)

**Description**: All workers run in EU, perform checks globally

**Rejected because**:
- ❌ Defeats purpose of regional monitoring
- ❌ EU → Asia checks show EU-Asia latency, not monitor's actual latency
- ❌ Can't detect region-specific outages

### Alternative 3: Kubernetes + Horizontal Pod Autoscaler

**Description**: Deploy workers in Kubernetes, auto-scale based on queue depth

**Rejected because**:
- ❌ Kubernetes overhead (control plane: 1GB+ RAM)
- ❌ Adds complexity (kubectl, YAML configs, container registry)
- ❌ NixOS provides similar benefits (declarative, reproducible)
- ✅ Can revisit at 100K+ monitors

---

## Migration Path

**Phase 1: Co-located Workers (Current Proposal)**
- Deploy workers on 5 existing infrastructure nodes
- Cost: $0 (uses existing nodes)
- Coverage: EU (3 nodes), Asia (2 nodes)

**Phase 2: Americas Coverage**
- Add worker to existing Canada node (ovh-canada)
- Cost: $0 (uses existing node)
- Coverage: EU (3), Asia (2), Americas (1)

**Phase 3: Dedicated Worker Nodes**
- Add Tokyo worker (Vultr $2.50/month)
- Add Singapore worker (Vultr $2.50/month)
- Cost: +$5/month
- Coverage: EU (3), Asia (4), Americas (1)

**Phase 4: Global Coverage**
- Add São Paulo (Americas), London (EU), Sydney (Oceania)
- Cost: +$7.50/month
- Coverage: 11 nodes, 6 regions

---

## Open Questions

1. **Queue priority**: Should critical monitors jump ahead of regular monitors?
   - Leaning: No, FIFO is simpler and fairer
   - Can revisit if users request SLA tiers

2. **Worker auto-scaling**: Should workers scale based on queue depth?
   - Leaning: No, fixed capacity is simpler
   - Manual scaling (add nodes) works for current scale

3. **Check result deduplication**: If 3 EU workers check same monitor, store 3 results or 1?
   - Leaning: Store all 3 (more data, better for debugging/statistics)
   - Can aggregate in queries if needed

---

## References

- [Oban Scaling Guide](https://getoban.pro/articles/scaling-oban)
- [NixOS Profiles Pattern](https://nixos.wiki/wiki/NixOS:extend_NixOS)
- [Uptrack Architecture Docs](/docs/architecture/region_check_worker.md)
- [Infrastructure Proposal](../establish-multi-region-monitoring-infrastructure/design.md)
