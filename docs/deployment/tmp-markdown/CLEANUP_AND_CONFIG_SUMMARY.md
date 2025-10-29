# TimescaleDB Cleanup & Pool Configuration Summary

**Date**: 2025-10-19
**Status**: COMPLETED ✅
**Focus**: Infrastructure cleanup and optimization for ClickHouse-only solution

---

## ✅ Work Completed

### 1. TimescaleDB Removal (COMPLETE)

**Objective**: Remove all TimescaleDB references before ClickHouse migration

**Actions**:
- ✅ Removed TimescaleDB from `infra/nixos/services/patroni.nix`
  - Changed from: `package = pkgs.postgresql_16.withPackages (ps: [ ps.timescaledb ])`
  - Changed to: `package = pkgs.postgresql_16`
  - Removed: `shared_preload_libraries = "timescaledb"`
  - Added comment: "TimescaleDB removed - using ClickHouse for time-series"

- ✅ Deleted `infra/nixos/services/timescaledb.nix` entirely

- ✅ Removed 6 references from `flake.nix`:
  - node-a colmena config (removed timescaledb import)
  - node-b colmena config (removed timescaledb import)
  - node-c colmena config (removed timescaledb import)
  - node-a nixosConfigurations (removed timescaledb import)
  - node-b nixosConfigurations (removed timescaledb import)
  - node-c nixosConfigurations (removed timescaledb import)

- ✅ Verification: Full codebase grep search for `timescaledb|TimescaleDB|timescale`
  - Only matches: Git history and documentation (no active code)
  - Conclusion: Clean removal ✅

---

### 2. Per-Repo Connection Pool Configuration

**Objective**: Optimize each PostgreSQL repo with workload-specific pool sizes

**Changes to `config/runtime.exs`**:

#### Before
```elixir
pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

config :uptrack, Uptrack.AppRepo, pool_size: pool_size
config :uptrack, Uptrack.ObanRepo, pool_size: pool_size
config :uptrack, Uptrack.ResultsRepo, pool_size: pool_size
```

#### After
```elixir
app_pool_size = String.to_integer(System.get_env("APP_POOL_SIZE") || "10")
oban_pool_size = String.to_integer(System.get_env("OBAN_POOL_SIZE") || "20")
results_pool_size = String.to_integer(System.get_env("RESULTS_POOL_SIZE") || "15")

# AppRepo - Light OLTP workload
config :uptrack, Uptrack.AppRepo,
  pool_size: app_pool_size,
  queue_target: 50,
  queue_interval: 5000

# ObanRepo - High job throughput
config :uptrack, Uptrack.ObanRepo,
  pool_size: oban_pool_size,
  queue_target: 100,
  queue_interval: 1000

# ResultsRepo - Batch inserts
config :uptrack, Uptrack.ResultsRepo,
  pool_size: results_pool_size,
  queue_target: 75,
  queue_interval: 2000
```

**Benefits**:
- ✅ AppRepo: 10 connections (light queries)
- ✅ ObanRepo: 20 connections (high job throughput)
- ✅ ResultsRepo: 15 connections (batch writes)
- ✅ Queue targets optimize connection waiting behavior
- ✅ Environment variable override capability per node

---

### 3. 5-Node Infrastructure Completion

**Objective**: Add India Weak node and complete flake.nix configuration

**Node Configurations**:

#### New Files
- ✅ `infra/nixos/node-india-strong.nix` - PG Replica + etcd (ARM64)
- ✅ `infra/nixos/node-india-weak.nix` - App-only + etcd (ARM64)

#### Updated `flake.nix`

**Colmena deployments added**:
```nix
node-india-strong = {
  deployment.targetHost = "144.24.133.171"
  tags = [ "replica" "oracle" "app" "postgres" "etcd" "arm64" ]
  imports = [...app, postgres, clickhouse...]
}

node-india-weak = {
  deployment.targetHost = "INDIA_WEAK_IP"
  tags = [ "app" "etcd" "oracle" "arm64" ]
  imports = [...app only...]
}
```

**nixosConfigurations added**:
```nix
node-india-strong = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux"
  modules = [...postgres, clickhouse...]
}

node-india-weak = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux"
  modules = [...app only...]
}
```

**Deployment scripts added**:
- `nix run deploy-node-india-strong`
- `nix run deploy-node-india-weak`
- `nix run install-node-india-strong`
- `nix run install-node-india-weak`

---

### 4. Environment Configuration Documentation

**Created `.env.example`** with:
- Database URLs for all 3 repos
- Per-repo pool size variables (APP, OBAN, RESULTS)
- Recommended values for each node:
  - **Germany (Primary)**: APP_POOL_SIZE=15, OBAN_POOL_SIZE=30, RESULTS_POOL_SIZE=20
  - **India Strong (Replica)**: APP_POOL_SIZE=10, OBAN_POOL_SIZE=25, RESULTS_POOL_SIZE=15
  - **Canada (App-only)**: APP_POOL_SIZE=8, OBAN_POOL_SIZE=20, RESULTS_POOL_SIZE=12
- ClickHouse, Oban, and Phoenix configuration variables

---

## 📊 Current Infrastructure State

### 5-Node Architecture
```
PostgreSQL PRIMARY: Germany (Hetzner ARM64)
├─ Replica 1: Austria (Contabo)
├─ Replica 2: India Strong (Oracle Free ARM64)
└─ Oban jobs: Germany, Austria, Canada, India Strong, India Weak

ClickHouse PRIMARY: Austria (Contabo)
├─ Replica 1: Germany (Hetzner ARM64)
└─ Replica 2: India Strong (Oracle Free ARM64)

etcd Cluster: All 5 nodes
├─ Quorum: 3/5
└─ Tolerates: 2 failures

App Nodes: All 5 nodes
├─ Tailscale mesh network
└─ HAProxy load balancing
```

### Database Connection Pools (Production Defaults)

| Repo | Workload | Default Pool | Germany | India | Canada |
|------|----------|--------------|---------|-------|--------|
| **AppRepo** | Light OLTP | 10 | 15 | 8 | 8 |
| **ObanRepo** | Job Queue | 20 | 30 | 20 | 20 |
| **ResultsRepo** | Batch Inserts | 15 | 20 | 12 | 12 |

---

## 🚀 Next Steps

### Immediate
1. **Test Pool Configuration**
   - Deploy to dev environment
   - Monitor connection usage per repo
   - Verify queue_target and queue_interval work correctly

2. **India Weak Node Setup**
   - Update INDIA_WEAK_IP in flake.nix with actual IP
   - Configure SSH access
   - Deploy with nixos-anywhere

### Phase 2: ClickHouse Migration (Ready)
1. Implement ResilientWriter for batching
2. Create ClickHouse tables for checks_raw
3. Migrate monitoring data from PostgreSQL
4. Set up ClickHouse replication between 3 nodes
5. Configure retention policies

### Phase 3: Deployment Sequence
```bash
# Deploy in order:
1. Germany (Primary DB)
2. Austria (CH Primary)
3. Canada (App)
4. India Strong (DB Replica)
5. India Weak (App + etcd quorum)
```

---

## 📝 Configuration Files Changed

**Modified**:
- `config/runtime.exs` - Per-repo pool sizing
- `flake.nix` - India nodes configuration
- `infra/nixos/services/patroni.nix` - TimescaleDB removed

**Created**:
- `.env.example` - Environment variable documentation
- `infra/nixos/node-india-weak.nix` - New node config
- `/docs/deployment/` - Restructured deployment documentation
- `/docs/OBAN_CLICKHOUSE_POOLING_ANALYSIS.md` - Technical analysis

**Deleted**:
- `infra/nixos/services/timescaledb.nix` - No longer needed

---

## ✅ Verification Checklist

- [x] No TimescaleDB references in active code
- [x] Per-repo pool sizes implemented
- [x] Environment variables documented
- [x] India Strong node in flake.nix
- [x] India Weak node in flake.nix
- [x] Deploy scripts for both nodes
- [x] Git commit completed
- [x] Ready for ClickHouse migration

---

## 🔧 Common Commands

**Build without deploying**:
```bash
nix run deploy-node-india-strong -- --build-only
```

**Deploy single node**:
```bash
colmena apply --on node-india-strong
```

**Check pool configuration**:
```bash
grep -A5 "pool_size" config/runtime.exs
```

**View environment variables**:
```bash
cat .env.example
```

---

**Status**: ✅ INFRASTRUCTURE CLEANUP COMPLETE
**Ready for**: ClickHouse migration
**Date Completed**: 2025-10-19
