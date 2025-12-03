# Establish Multi-Region Monitoring Infrastructure

## Summary

Establish a production-grade, multi-region infrastructure for Uptrack's monitoring service with:
- **VictoriaMetrics cluster** with separated compute (Netcup) and storage (HostHatch) for independent scaling
- **PostgreSQL HA** with Patroni/etcd for automatic failover
- **Tailscale mesh network** for secure cross-provider communication

## Why

Uptrack needs production infrastructure to support 10,000 monitors (100 users × 100 monitors each) running checks every 45 seconds with 15-month metrics retention.

Current challenges:
- **Storage scaling**: VictoriaMetrics storage needs to grow independently from compute
- **Multi-provider complexity**: Netcup (Germany) + Oracle (India) + HostHatch requires secure cross-provider networking
- **High availability required**: Auto-failover for PostgreSQL prevents 5-60 min manual downtime
- **Cost optimization**: Cheap storage VPS (HostHatch) for vmstorage, compute VPS (Netcup) for vminsert/vmselect
- **Geographic distribution**: EU nodes for low-latency HA cluster, India nodes for DR and Asian users

Without this infrastructure, Uptrack cannot launch to production users.

## What

### Current Inventory

| Location | Provider | Specs | Role |
|----------|----------|-------|------|
| Nuremberg | Netcup G12 Pro | 4 CPU, 8GB RAM, 512GB NVMe | nbg-1 (compute) |
| Nuremberg | Netcup G12 Pro | 4 CPU, 8GB RAM, 512GB NVMe | nbg-2 (compute) |
| Nuremberg | Netcup G12 Pro | 4 CPU, 8GB RAM, 512GB NVMe | nbg-3 (compute + vmstorage) |
| India | Oracle Cloud | 3 OCPU, 18GB RAM, 46GB | india-strong (DR) |
| India | Oracle Cloud | 1 OCPU, 6GB RAM, ~40GB | india-weak (backups) |
| Amsterdam | HostHatch | 2 CPU, 2GB RAM, 1TB+ NVMe | storage-1 (vmstorage) |

### In Scope
- 6-node infrastructure deployment (5 existing + 1 HostHatch storage)
- VictoriaMetrics cluster with **hybrid architecture**:
  - vminsert/vmselect on Netcup (compute)
  - vmstorage on nbg-3 + storage-1 (2-node HA with replicationFactor=2)
- PostgreSQL HA with Patroni and etcd (3-node quorum on Netcup)
- Tailscale mesh network for secure inter-node communication
- India nodes for DR replica and backup storage
- Monitoring stack (Prometheus, Loki, Alertmanager)

### Out of Scope
- Application deployment (Elixir/Phoenix app)
- Application-level monitoring configuration
- DNS and load balancing configuration
- SSL/TLS certificate management

## Affected Capabilities

This change establishes new capabilities:

1. **infrastructure/compute** - Node provisioning and lifecycle management
2. **infrastructure/networking** - Tailscale mesh network and firewall rules
3. **infrastructure/metrics-storage** - VictoriaMetrics cluster with separated compute/storage
4. **infrastructure/database-ha** - PostgreSQL with Patroni/etcd for automatic failover
5. **infrastructure/backups** - Backup and disaster recovery procedures

## Architecture Overview

```
COMPUTE LAYER (Netcup Nuremberg - Low Latency <5ms)
┌─────────────────────────────────────────────────────────────┐
│  nbg-1                    nbg-2                    nbg-3    │
│  ├─ vminsert              ├─ vminsert              ├─ vmselect (backup) │
│  ├─ vmselect              ├─ vmselect              ├─ vmstorage ◄─┐     │
│  ├─ PostgreSQL (primary)  ├─ PostgreSQL (replica)  ├─ etcd (3/3)  │     │
│  └─ etcd (1/3)            └─ etcd (2/3)            └─ PostgreSQL  │     │
└─────────────────────────────────────────────────────────────┼─────┘
                              │                               │
                              │ Tailscale (encrypted)         │ replicationFactor=2
                              ▼                               │
STORAGE LAYER (HostHatch Amsterdam - 5-10ms to Nuremberg)     │
┌─────────────────────────────────────────────────────────────┼─────┐
│  storage-1                                                  │     │
│  └─ vmstorage ◄─────────────────────────────────────────────┘     │
│     1TB+ NVMe (dedicated)                                         │
│                                                                   │
│  (Future: add storage-2, storage-3 for 3-node HA)                 │
└───────────────────────────────────────────────────────────────────┘
                              │
                              │ Tailscale (encrypted)
                              ▼
DR LAYER (Oracle Cloud India - 80-120ms latency)
┌─────────────────────────────────────────────────────────────┐
│  india-strong                         india-weak            │
│  ├─ PostgreSQL (async replica)        ├─ Backups (PG + VM)  │
│  ├─ vmselect (read from EU storage)   ├─ Loki               │
│  └─ vmagent (local metrics)           └─ Alertmanager       │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Strategy

### Phase 1: Foundation
- Deploy Tailscale on all existing nodes (3 Netcup + 2 Oracle)
- Setup etcd cluster on Netcup nodes
- Configure PostgreSQL HA with Patroni

### Phase 2: Storage Layer (Hybrid Approach)
- Purchase 1 HostHatch storage VPS (Amsterdam, ~€6/mo)
- Deploy vmstorage on storage-1 (1TB dedicated storage)
- Deploy vmstorage on nbg-3 (512GB shared with PG async replica)
- Configure replicationFactor=2 for HA (data on both nodes)
- Join storage-1 to Tailscale network

### Phase 3: Compute Layer
- Deploy vminsert on nbg-1, nbg-2 with `-replicationFactor=2`
- Deploy vmselect on nbg-1, nbg-2, nbg-3, india-strong
- Configure routing to both vmstorage nodes (nbg-3, storage-1)

### Phase 4: DR and Monitoring
- Setup PostgreSQL async replica on india-strong
- Deploy Prometheus, Loki, Alertmanager
- Configure backups to india-weak

## Open Questions

1. ~~**HostHatch Region**: Amsterdam (5-10ms to Nuremberg) vs Nuremberg (if available)?~~
   - **Resolved**: Amsterdam for geographic redundancy

2. ~~**Replication Factor**: Should VictoriaMetrics use replication factor 2?~~
   - **Resolved**: Use RF=2 with 2-node hybrid setup (nbg-3 + storage-1) for HA from day one

3. **PostgreSQL on Netcup**: Use 512GB NVMe for PG data, or separate partition?
   - Proposal: Single partition, PostgreSQL data <50GB expected

4. **nbg-3 Disk Monitoring**: vmstorage shares 512GB with PG async replica
   - Action: Monitor disk usage, expected ~80GB combined (31GB VM + 50GB PG)

## Success Criteria

- [ ] All 6 nodes communicating via Tailscale private network
- [ ] VictoriaMetrics cluster: vminsert/vmselect on Netcup, vmstorage on nbg-3 + storage-1
- [ ] vmstorage HA working with replicationFactor=2 (data on both nodes)
- [ ] PostgreSQL primary can failover automatically in <30 seconds
- [ ] Metrics retention working (15 months of data)
- [ ] Storage expandable by adding HostHatch nodes (storage-2, storage-3)
- [ ] India nodes serving as DR for PostgreSQL and vmselect
- [ ] Documentation complete (architecture diagrams, runbooks)

## References

- [VictoriaMetrics Cluster Documentation](https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/)
- [VictoriaMetrics Capacity Planning](https://docs.victoriametrics.com/guides/understand-your-setup-size/)
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [etcd Documentation](https://etcd.io/docs/)
- [Tailscale Best Practices](https://tailscale.com/kb/1019/subnets/)
