# ClickHouse Integration Documentation

Complete guide for integrating ClickHouse as a time-series analytics database for Uptrack's monitoring SaaS.

---

## 📚 Documentation Index

### Decision & Architecture

- **[ch vs ecto_ch](./ch_vs_ecto_ch.md)** ⭐ **START HERE**
  - Comprehensive comparison of ClickHouse client libraries
  - Why `ch` + ResilientWriter is the right choice for Uptrack
  - When to use each approach
  - Decision matrix and recommendations

- **[ResilientWriter Pattern](./resilient_writer.md)** ⭐ **CRITICAL**
  - What ResilientWriter is and why it's essential
  - Batching, spooling, and retry logic explained
  - Complete implementation guide
  - Production monitoring and troubleshooting
  - Performance expectations

### Related Architecture Docs

- **[Architecture Summary](../architecture/ARCHITECTURE-SUMMARY.md)** - ClickHouse 3-node cluster design
- **[Oban + ClickHouse Analysis](../OBAN_CLICKHOUSE_POOLING_ANALYSIS.md)** - Multi-repo pooling strategy
- **[Deployment Guide](../deployment/README.md)** - ClickHouse node deployment

---

## 🎯 Quick Decision Guide

### "Should I use ecto_ch?"

| Scenario | Answer | Why |
|----------|--------|-----|
| Pure time-series monitoring | **NO** ❌ | Use `ch` + ResilientWriter |
| Complex analytics queries | Maybe | But still prefer raw SQL via `ch` |
| Mixed OLTP + Analytics | Maybe | Consider separate read models |
| Team knows Ecto well | Maybe | But doesn't justify overhead |

**For Uptrack**: Always use `ch` + ResilientWriter ✅

---

### "Do I need ResilientWriter?"

| Characteristic | Needed? |
|-----------------|---------|
| >100 events/sec | ✅ YES |
| Data loss unacceptable | ✅ YES |
| Remote ClickHouse (network) | ✅ YES |
| Multi-node deployment | ✅ YES |
| Real-time inserts critical | ✅ YES |

**For Uptrack**: Absolutely essential ✅

---

## 🏗️ Architecture

```
Monitoring Application
├─ Oban Job Queue (all 5 nodes)
│  └─ CheckMonitorJob (1K checks/sec total)
│
├─ ResilientWriter (GenServer on each node)
│  ├─ Accumulates ~200 rows
│  ├─ Batches every 5 seconds
│  ├─ Spools to disk on failure
│  └─ Retries with exponential backoff
│
└─ ClickHouse (3-node cluster)
   ├─ Austria (Primary)
   ├─ Germany (Replica)
   └─ India Strong (Replica)
```

---

## 📦 Dependencies

```elixir
# mix.exs
defp deps do
  [
    # ClickHouse client (lightweight HTTP driver)
    {:ch, "~> 0.2"},

    # For JSON spooling (optional but recommended)
    {:jason, "~> 1.4"},

    # For background work (already in dependencies)
    {:oban, "~> 2.0"},
  ]
end
```

---

## 🚀 Implementation Timeline

### Phase 1: Planning (Done ✅)
- [x] Compare `ch` vs `ecto_ch` → Use `ch`
- [x] Design ResilientWriter pattern
- [x] Plan spool directory and retry logic

### Phase 2: Development
- [ ] Implement ResilientWriter GenServer
- [ ] Add spool directory to NixOS config
- [ ] Add Prometheus metrics
- [ ] Create test suite

### Phase 3: Integration
- [ ] Integrate with Oban job workers
- [ ] Add to Phoenix supervision tree
- [ ] Configure environment variables
- [ ] Test failure scenarios

### Phase 4: Deployment
- [ ] Deploy to development
- [ ] Monitor metrics in staging
- [ ] Deploy to production
- [ ] Verify data flow

### Phase 5: Monitoring
- [ ] Set up Prometheus alerts
- [ ] Configure log aggregation
- [ ] Create runbooks
- [ ] Schedule on-call training

---

## 💡 Key Concepts

### Batching
Accumulate ~200 rows in memory, send as single HTTP request to ClickHouse. Reduces requests from 1000/sec to ~5/sec, improves throughput 100x.

### Spooling
When ClickHouse unavailable, write batches to disk. Retry when ClickHouse recovers. Ensures zero data loss.

### Retry Logic
Exponential backoff (500ms → 1s → 2s → 4s → ... → 30s max). Prevents overwhelming ClickHouse while it recovers.

### Metrics
Track rows sent, rows spooled, retry count, batch latency. Alert on anomalies (spool growth, high latency).

---

## 📊 Performance Goals

### Target Metrics

| Metric | Target | Current |
|--------|--------|---------|
| **Throughput** | >10K rows/sec | TBD |
| **P99 Latency** | <500ms | TBD |
| **Availability** | >99.95% | TBD |
| **Data loss** | 0 events | TBD |
| **Spool disk used** | <100MB avg | TBD |

---

## 🔧 Configuration

### Environment Variables

```bash
# ClickHouse connection
CLICKHOUSE_HOST=clickhouse.internal  # Tailscale IP
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default

# ResilientWriter
RESILIENT_WRITER_BATCH_SIZE=200
RESILIENT_WRITER_BATCH_TIMEOUT_MS=5000
RESILIENT_WRITER_MAX_RETRIES=10
RESILIENT_WRITER_SPOOL_DIR=/var/spool/uptrack/clickhouse
```

### NixOS Configuration

```nix
# infra/nixos/services/resilient_writer.nix (to be created)
{
  # Create spool directory
  systemd.tmpfiles.rules = [
    "d /var/spool/uptrack/clickhouse 0755 uptrack uptrack - -"
  ];

  # Permissions
  users.users.uptrack.extraGroups = [ "uptrack" ];
}
```

---

## 🐛 Troubleshooting Guide

### Spool Growing (ClickHouse Unavailable)
1. Check ClickHouse status
2. Check network connectivity
3. Review ClickHouse logs
4. Verify Tailscale connection

### High Batch Latency
1. Check ClickHouse performance
2. Monitor memory usage
3. Check network latency
4. Review ClickHouse slow queries

### Data Not Appearing
1. Verify ResilientWriter is running
2. Check spool directory
3. Review error logs
4. Manually inspect ClickHouse tables

See **[ResilientWriter](./resilient_writer.md#troubleshooting)** for detailed troubleshooting.

---

## 📈 Monitoring

### Prometheus Metrics to Track

```
clickhouse_rows_sent_total          # Total rows inserted
clickhouse_rows_spooled_total       # Rows written to spool
clickhouse_spool_size_bytes         # Current spool size
clickhouse_batch_latency_ms         # Batch processing time
clickhouse_retry_count_total        # Total retries
```

### Alerts to Create

- `ClickHouseBatchSpooling`: Rows spooled > 1000 in 5 min
- `ClickHouseHighLatency`: P95 latency > 1 second
- `ClickHouseSpoolDiskFull`: Spool size > 10GB
- `ClickHouseInsertError`: Insert failures > 5 in 10 min

---

## 🎓 Learning Path

**For new team members**:

1. **Start with** [ch vs ecto_ch](./ch_vs_ecto_ch.md)
   - Understand the architectural decision
   - Learn why we don't use ecto_ch

2. **Then read** [ResilientWriter](./resilient_writer.md)
   - Understand batching, spooling, retries
   - See implementation examples

3. **Review** monitoring setup
   - Learn what metrics to track
   - Understand alert conditions

4. **Study** architecture
   - See how it fits in 5-node infrastructure
   - Understand data flow

5. **Hands-on**:
   - Deploy to development
   - Trigger failure scenarios
   - Observe spooling behavior
   - Test recovery

---

## ❓ FAQ

**Q: Why not use ecto_ch?**
A: It adds unnecessary abstraction layers (Ecto changesets, validation) that we don't need for append-only time-series. We prefer performance and simplicity.

**Q: What if ClickHouse goes down?**
A: ResilientWriter spools to disk and retries. Zero data loss. When ClickHouse recovers, spool flushes automatically.

**Q: How much disk space for spool?**
A: Usually <100MB. Each batch is ~10KB uncompressed. At 1K rows/sec, full day of continuous failure = ~850MB. Allocate 10GB to be safe.

**Q: Can I use this on a single node?**
A: Yes, but unnecessary. ResilientWriter is most valuable in multi-node setups where ClickHouse is remote/unreliable.

**Q: What's the latency impact?**
A: ~100-500ms from check completion to data in ClickHouse (depends on batch timeout). Acceptable for monitoring use case.

**Q: Can I integrate with Kafka instead?**
A: Yes, but ResilientWriter is simpler. Kafka adds operational complexity (separate cluster, maintenance). ResilientWriter is built-in.

---

## 📞 Support & Questions

- **Architecture questions**: See [Architecture Summary](../architecture/ARCHITECTURE-SUMMARY.md)
- **Implementation questions**: See [ResilientWriter Implementation](./resilient_writer.md#implementation-guide)
- **Troubleshooting**: See [Troubleshooting Guide](./resilient_writer.md#troubleshooting)
- **Performance tuning**: See [Performance Expectations](./resilient_writer.md#performance-expectations)

---

## 📝 Related Documentation

- **Deployment**: [/docs/deployment/](../deployment/)
- **Architecture**: [/docs/architecture/](../architecture/)
- **Configuration**: [/docs/CLEANUP_AND_CONFIG_SUMMARY.md](../CLEANUP_AND_CONFIG_SUMMARY.md)

---

**Last Updated**: 2025-10-19
**Status**: Documentation Complete
**Next Phase**: Implementation
