# Establish Multi-Region Monitoring Infrastructure

## Summary

Establish a production-grade, multi-region infrastructure for Uptrack's monitoring service with VictoriaMetrics cluster for metrics storage, PostgreSQL high-availability with Patroni, and a provider-agnostic architecture enabling zero-downtime migration from Hostkey (Italy) to Netcup (Austria).

## Why

Uptrack needs production infrastructure to support 10,000 monitors (100 users × 100 monitors each) running checks every 45 seconds with 15-month metrics retention.

Current challenges:
- **No infrastructure deployed** (greenfield deployment on 3 Hostkey nodes + 2 Oracle Cloud nodes)
- **Multi-provider complexity**: Hostkey (Italy) + Oracle (India) requires secure cross-provider networking
- **High availability required**: Auto-failover for PostgreSQL prevents 5-60 min manual downtime
- **Future migration planned**: Will move from Hostkey ($5.23/node) to Netcup ($6.78/node) for better specs (6 vCPU, 256GB storage)
- **Geographic distribution**: EU nodes for low-latency HA cluster, India nodes serve Asian users and backups

Without this infrastructure, Uptrack cannot launch to production users.

## What

### In Scope
- 5-node infrastructure deployment with clear roles
- VictoriaMetrics cluster (3 vmstorage, 2 vminsert, 3 vmselect)
- PostgreSQL HA with Patroni and etcd (3-node quorum in EU)
- Tailscale mesh network for secure inter-node communication
- Generic node naming for provider-agnostic configuration
- Monitoring stack (Prometheus, Loki, Alertmanager)
- Backup infrastructure (PostgreSQL dumps, VM snapshots)
- Migration strategy from Hostkey to Netcup

### Out of Scope
- Application deployment (Elixir/Phoenix app)
- Application-level monitoring configuration (handled separately)
- DNS and load balancing configuration
- SSL/TLS certificate management
- Alerting rules and notification channels (monitoring policy)

## Affected Capabilities

This change establishes new capabilities:

1. **infrastructure/compute** - Node provisioning and lifecycle management
2. **infrastructure/networking** - Tailscale mesh network and firewall rules
3. **infrastructure/metrics-storage** - VictoriaMetrics cluster architecture
4. **infrastructure/database-ha** - PostgreSQL with Patroni/etcd for automatic failover
5. **infrastructure/backups** - Backup and disaster recovery procedures
6. **infrastructure/monitoring** - Observability stack (Prometheus, Loki, Alertmanager)

## Implementation Strategy

### Phase 1: Current State (Hostkey Italy)
- Deploy all services on 3 Italy nodes + 2 India nodes
- Establish Tailscale network (100.64.1.x IPs)
- Configure VictoriaMetrics cluster with 3 vmstorage
- Setup PostgreSQL HA with etcd/Patroni
- Estimated timeline: 2-3 weeks

### Phase 2: Add Netcup Nodes (Parallel)
- Purchase 3 Netcup Austria nodes
- Add to Tailscale network (100.64.1.21-23 temp IPs)
- Expand VictoriaMetrics cluster to 6 vmstorage
- Setup PostgreSQL replication from Hostkey to Netcup
- Estimated timeline: 1 week

### Phase 3: Migrate Workloads
- Failover PostgreSQL primary to Netcup
- Monitor stability (1 week)
- Remove Hostkey nodes from VM cluster
- Estimated timeline: 1 week

### Phase 4: Cleanup
- Reassign Tailscale IPs (Netcup becomes 100.64.1.1-3)
- Rename hostnames (Netcup becomes eu-a, eu-b, eu-c)
- Cancel Hostkey subscriptions
- Estimated timeline: 1 day

## Open Questions

1. **Retention Policy**: Should we implement different retention for free vs paid users in VictoriaMetrics?
   - Current plan: 15 months for all users, revisit when storage usage grows

2. **Backup Frequency**: How often should PostgreSQL backups run to india-w node?
   - Proposal: Daily full backup + continuous WAL archiving

3. **etcd Disk Usage**: Should we set up etcd on separate disk/partition?
   - Current plan: Use same disk (etcd uses <2GB), monitor closely

4. **Monitoring Scope**: Should india-s run Prometheus for global metrics, or just regional?
   - Proposal: india-s runs Prometheus scraping all nodes globally

5. **Emergency Procedures**: Document manual failover procedures in case Patroni fails?
   - Proposal: Yes, include in operational runbook (separate from this spec)

## Success Criteria

- [ ] All 5 nodes communicating via Tailscale private network
- [ ] VictoriaMetrics cluster accepting writes and serving queries
- [ ] PostgreSQL primary can failover automatically in <30 seconds
- [ ] Metrics retention working (15 months of data)
- [ ] Backups running daily to india-w
- [ ] Monitoring dashboards showing cluster health
- [ ] Zero-downtime migration from Hostkey to Netcup demonstrated
- [ ] Documentation complete (architecture diagrams, runbooks)

## References

- [VictoriaMetrics Cluster Documentation](https://docs.victoriametrics.com/Cluster-VictoriaMetrics.html)
- [Patroni Documentation](https://patroni.readthedocs.io/)
- [etcd Documentation](https://etcd.io/docs/)
- [Tailscale Best Practices](https://tailscale.com/kb/1019/subnets/)
- [NixOS Deployment Guide](https://nixos.org/manual/nixos/stable/)
