# Uptrack Infrastructure Overview

## Production Architecture (5 Nodes)

| Node Name | Location | Region | Provider | vCPU | RAM | Storage | Role | Tailscale IP | Cost/Month |
|-----------|----------|--------|----------|------|-----|---------|------|--------------|------------|
| **germany** | Germany | Europe | Netcup ARM G11 | 6 | 8 GB | 256 GB | PG Primary + VM Node | 100.64.0.1 | $7.11 |
| **austria** | Austria | Europe | Netcup ARM G11 | 6 | 8 GB | 256 GB | PG Replica + VM Node | 100.64.0.2 | $7.11 |
| **canada** | Canada | Americas | OVH VPS-1 | 4 | 8 GB | 75 GB | App-only + VM Node | 100.64.0.3 | $4.20 |
| **india-rworker** | India | APAC | Oracle Free ARM64 | 1 | 6 GB | ~40 GB | Backups & Logs | 100.64.0.5 | Free |

**Total Monthly Cost**: $18.42 (~$221/year)

## Legacy Nodes (Deprecated - To Be Removed)

| Node Name | Old Name | IP | Provider | Status |
|-----------|----------|-----|----------|--------|
| **hetzner-primary** | node-a | 91.98.89.119 | Hetzner ARM64 | ⚠️ Will be decommissioned after migration to Netcup |
| **contabo-secondary** | node-b | 185.237.12.64 | Contabo x86_64 | ⚠️ Will be decommissioned after migration to Netcup |
| **contabo-tertiary** | node-c | 147.93.146.35 | Contabo x86_64 | ⚠️ Will be decommissioned after migration to Netcup |

## Service Distribution

### Full Stack Nodes
- Uptrack App
- PostgreSQL Primary/Replica
- VictoriaMetrics Node
- HAProxy (load balancer)

**Current**: hetzner-primary (node-a)
**Planned**: Germany (Netcup)

### Worker Nodes
- Uptrack App
- PostgreSQL Replica
- VictoriaMetrics Node

**Current**: contabo-secondary (node-b), contabo-tertiary (node-c)
**Planned**: Austria (Netcup)

### App-Only Nodes
- Uptrack App only
- No database services

**Current**: None
**Planned**: Leaseweb Washington

### App + etcd Nodes
- Uptrack App
- etcd (distributed coordination)
- No database services

**Current**: india-rworker (india-rworker)
**Planned**: India RWorker (Oracle)

## NixOS Configuration Mapping

```
infra/nixos/regions/
├── europe/
│   ├── hetzner-primary/       # 91.98.89.119 (current)
│   ├── contabo-secondary/     # 185.237.12.64 (current)
│   ├── contabo-tertiary/      # 147.93.146.35 (current)
│   ├── netcup-germany/        # TBD (planned - PG Primary + CH Replica)
│   └── netcup-austria/        # TBD (planned - CH Primary + PG Replica)
│
├── americas/
│   └── leaseweb-washington/   # TBD (planned - App-only)
│
└── asia/
    └── india-hyderabad/
        └── rworker/           # 144.24.150.48 (Backups & Logs)
```

## Database Architecture

### PostgreSQL (Primary/Replica Setup)
- **Primary**: Germany (Netcup) - planned
- **Replicas**:
  - Austria (Netcup) - planned

### VictoriaMetrics Cluster (Time-Series Database)
- **Cluster Nodes**: TBD
  - Germany (Netcup) - planned
  - Austria (Netcup) - planned
  - Canada (OVH) - planned

### etcd (Distributed Coordination)
- India RWorker (Oracle) - current

## Migration Path

### Phase 1: Current (Legacy Providers)
- ✅ Hetzner primary (node-a)
- ✅ Contabo secondary (node-b)
- ✅ Contabo tertiary (node-c)
- ✅ Oracle India (india-rworker)

### Phase 2: Netcup Migration (Planned)
1. Deploy Germany (Netcup) as new PG Primary + VM Node
2. Deploy Austria (Netcup) as PG Replica + VM Node
3. Migrate traffic from Hetzner/Contabo to Netcup
4. Decommission Hetzner/Contabo nodes

### Phase 3: North America Expansion (Planned)
1. Deploy Leaseweb Washington as app-only node
2. Route US traffic to Washington node

## Deployment Commands

### Current Nodes
```bash
# Deploy all current nodes
colmena apply

# Deploy by region
colmena apply --on @europe        # All Europe nodes
colmena apply --on @asia          # All Asia nodes

# Deploy specific node
colmena apply --on hetzner-primary
colmena apply --on india-rworker
```

### Future Nodes (when added)
```bash
colmena apply --on netcup-germany
colmena apply --on netcup-austria
colmena apply --on leaseweb-washington
```

## Cost Analysis

### Current Infrastructure
- Hetzner: ? EUR/month
- Contabo (2x): ? EUR/month
- Oracle (1x): Free
- **Total**: ? EUR/month

### Planned Infrastructure
- Netcup Germany: $7.11/month
- Netcup Austria: $7.11/month
- Leaseweb Washington: $4.20/month
- Oracle (1x): Free
- **Total**: $18.42/month (~16.90 EUR/month)

**Cost Savings**: TBD after migration from Hetzner/Contabo

## Next Steps

1. **Add Netcup nodes** to NixOS config
2. **Add Leaseweb Washington** to NixOS config
3. **Test deployments** to new providers
4. **Set up replication** (PostgreSQL only - VictoriaMetrics cluster handles time-series)
5. **Migrate traffic** from old to new infrastructure
6. **Decommission** Hetzner/Contabo nodes
