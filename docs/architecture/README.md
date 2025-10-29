# Uptrack Architecture Documentation

This directory contains all architecture-related documentation for Uptrack's infrastructure and design decisions.

---

## 📚 Documentation Index

### Core Architecture

**[ARCHITECTURE-SUMMARY.md](./ARCHITECTURE-SUMMARY.md)** - Quick Reference ⭐
- Node specifications and costs
- Database distribution
- Network topology
- Scaling roadmap
- **Start here** for a quick overview

**[final-5-node-architecture.md](./final-5-node-architecture.md)** - Complete Specification
- Detailed 5-node setup
- Storage allocation
- Failover scenarios
- Deployment checklist
- Troubleshooting guide

### Design Principles

**[oracle-netcup-ovh-architecture.md](./oracle-netcup-ovh-architecture.md)** - Provider Analysis
- 3-node Oracle + Netcup architecture (legacy)
- Cost breakdown
- Regional coverage
- Alternative to current 5-node setup

---

## 🎯 Current Architecture (2025-10-29)

### Final 5-Node Setup

```
Germany (Netcup 256GB) - PostgreSQL PRIMARY + VictoriaMetrics node
Austria (Netcup 256GB) - PostgreSQL replica + VictoriaMetrics node
Canada (OVH 75GB) - App-only + VictoriaMetrics node
India Strong (Oracle Free 145GB) - PostgreSQL replica
India Weak (Oracle Free) - App-only + etcd

Total Cost: ~$23/month
```

### Key Features
- ✅ PostgreSQL with Patroni HA
- ✅ VictoriaMetrics cluster for time-series data
- ✅ Supports 10K monitors
- ✅ 5-node etcd cluster (optimal HA)
- ✅ 3 continents coverage

---

## 🗺️ Reading Order

### For New Team Members
1. **ARCHITECTURE-SUMMARY.md** - Get the big picture
2. **why-separate-database-primaries.md** - Understand why we made key decisions
3. **final-5-node-architecture.md** - Deep dive into implementation

### For Operations
1. **final-5-node-architecture.md** - Deployment and troubleshooting
2. **ARCHITECTURE-SUMMARY.md** - Quick reference for commands

### For Future Changes
1. **why-separate-database-primaries.md** - Understand the constraints
2. **final-5-node-architecture.md** - See current implementation
3. **ARCHITECTURE-SUMMARY.md** - Check scaling roadmap

---

## 🔄 Document History

| Date | Document | Change |
|------|----------|--------|
| 2025-10-19 | final-5-node-architecture.md | Removed Poland node, updated to 5 nodes |
| 2025-10-19 | ARCHITECTURE-SUMMARY.md | Created quick reference guide |
| 2025-10-10 | why-separate-database-primaries.md | Initial separation principle doc |
| 2025-10-10 | oracle-netcup-ovh-architecture.md | Initial provider comparison |

---

## 📋 Related Documentation

Outside this directory:

- **[../DEPLOYMENT.md](../DEPLOYMENT.md)** - Step-by-step deployment guide
- **[../NIXOS-SETUP-COMPLETE.md](../NIXOS-SETUP-COMPLETE.md)** - NixOS configuration
- **[../deployment-plan.md](../deployment-plan.md)** - High-level deployment strategy
- **[../nixos-deployment-guide.md](../nixos-deployment-guide.md)** - NixOS-specific guide

---

## 🤔 Common Questions

### Why 5 nodes instead of 6?
**Answer**: Removed Poland to save $50/year. India Weak provides the 5th etcd member (keeps odd number for optimal consensus). See ARCHITECTURE-SUMMARY.md → "Why NOT Poland Node?"

### Why VictoriaMetrics instead of ClickHouse?
**Answer**: VictoriaMetrics is purpose-built for time-series metrics with lower operational complexity, better Prometheus ecosystem integration, and lower resource requirements. See docs/tech-stack/database-strategy.md

### How do we scale to 20K monitors?
**Answer**: Upgrade Netcup nodes to 512 GB (VPS 2000 ARM G11). See final-5-node-architecture.md → "Scaling Strategy"

### Do we need gRPC?
**Answer**: **NO**. Current HTTP + native protocols are optimal for the monolith architecture. See ARCHITECTURE-SUMMARY.md → "Why Primary-Replica Model?"

### How much does it cost to add a region?
**Answer**: ~$4-5/month for an app-only node (no databases needed). See final-5-node-architecture.md → "Scaling Options"

---

## 🔍 Quick Links

### Diagrams & Visualizations
- Network topology: [final-5-node-architecture.md#network-topology](./final-5-node-architecture.md#network-topology)
- Database distribution: [ARCHITECTURE-SUMMARY.md#database-distribution](./ARCHITECTURE-SUMMARY.md#database-distribution)

### Cost Breakdowns
- Current setup: [ARCHITECTURE-SUMMARY.md#quick-reference](./ARCHITECTURE-SUMMARY.md#quick-reference)
- Scaling projections: [final-5-node-architecture.md#cost-breakdown--projections](./final-5-node-architecture.md#cost-breakdown--projections)
- Provider comparison: [oracle-netcup-ovh-architecture.md#cost-breakdown](./oracle-netcup-ovh-architecture.md#cost-breakdown)

### Technical Specs
- Storage allocation: [final-5-node-architecture.md#storage-allocation](./final-5-node-architecture.md#storage-allocation)
- Database configs: [final-5-node-architecture.md#database-distribution](./final-5-node-architecture.md#database-distribution)
- Capacity limits: [ARCHITECTURE-SUMMARY.md#capacity--limits](./ARCHITECTURE-SUMMARY.md#capacity--limits)

---

**Last Updated**: 2025-10-19
**Maintained by**: Infrastructure Team
