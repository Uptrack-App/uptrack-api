# Uptrack Architecture Integration - PostgreSQL Replica Setup
**Date**: 2025-10-21
**Status**: Planning Phase → Immediate Action Required
**Context**: Transitioning India Strong from standalone to 5-node clustered architecture

---

## Executive Summary

India Strong is **ONE NODE** of a distributed 5-node architecture. Currently it's being configured in isolation, but it needs to be integrated into a **PostgreSQL Patroni cluster** (3 nodes HA) that spans:

| Node | Role | Provider | Region |
|------|------|----------|--------|
| **Germany** | PostgreSQL PRIMARY | Netcup | EU |
| **Austria** | PostgreSQL Replica | Netcup | EU |
| **India Strong** | PostgreSQL Replica | Oracle Free | APAC |

---

## 5-Node Architecture Overview

The full system has 5 nodes across 3 continents:

```
EUROPE (2 nodes)
├─ Germany (Netcup): PostgreSQL PRIMARY + ClickHouse replica
└─ Austria (Netcup): ClickHouse PRIMARY + PostgreSQL replica

NORTH AMERICA (1 node)
└─ Canada (OVH): App-only

APAC (2 nodes)
├─ India Strong (Oracle Free): PostgreSQL replica ← YOU ARE HERE
└─ India Weak (Oracle Free): App-only + etcd member
```

**Key Architecture Principle**: Database primaries separated on different nodes
- PostgreSQL PRIMARY: Germany 🇩🇪
- ClickHouse PRIMARY: Austria 🇦🇹
- Failure isolation: Each primary failure doesn't affect the other

---

## Current State: India Strong

### ✅ What's Working
- System boots cleanly (SSH available ~10 seconds)
- PostgreSQL 17.5 JIT configured in `/Users/le/repos/uptrack/infra/nixos/node-india-strong-minimal.nix`
- Configuration includes: Patroni, Tailscale, basic firewall
- Build process: Tested and stable (--max-jobs 3 optimal)

### ❌ What's Not Yet Done
- **CRITICAL**: NixOS flake configuration NOT activated on system
  - System still using old `/etc/nixos/configuration.nix`
  - Flake built locally on Mac but never `switch` to on remote
- PostgreSQL service not running (because old config doesn't have it)
- etcd not running (consensus cluster not yet initialized)
- Patroni not running (will auto-start once flake is switched)
- Tailscale not configured (private network mesh not set up)

---

## Root Cause: Configuration Mismatch

The flake configuration exists and builds successfully, but **it's never been activated** on the system.

### Evidence
```bash
# On local Mac
/Users/le/repos/uptrack/flake.nix exists ✅
/Users/le/repos/uptrack/infra/nixos/node-india-strong-minimal.nix exists ✅

# On remote system
/etc/nixos/configuration.nix exists (OLD CONFIG) ← THIS IS ACTIVE
/etc/nixos/flake.nix DOES NOT EXIST ← WE NEED TO CREATE THIS
```

### Why This Happened
Previous deployments built the flake locally but didn't complete the `switch` step to make it active on the remote system.

---

## Next Steps: Activate Flake Configuration

### IMMEDIATE (Next 15 minutes)

#### Step 1: Copy Flake to Remote System
```bash
# From Mac
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "rm -rf /etc/nixos"
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "mkdir -p /etc/nixos"

# Copy flake and configs
rsync -av /Users/le/repos/uptrack/ root@152.67.179.42:/home/le/uptrack/
```

#### Step 2: Activate Flake (on remote system)
```bash
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "cd /home/le/uptrack && \
  nixos-rebuild switch --flake '.#node-india-strong' --max-jobs 3 && \
  echo 'Flake activated successfully!'"
```

#### Step 3: Verify PostgreSQL Running
```bash
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "systemctl status postgresql"
```

### AFTER ACTIVATION (Next 30-60 minutes)

#### Step 4: Configure Patroni
- Patroni service will auto-start (already in config)
- Needs to connect to Germany (PostgreSQL PRIMARY)
- Configuration via environment variables or config file

#### Step 5: Verify Cluster
```bash
# On India Strong
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "patronictl list uptrack-pg-cluster"

# Should show:
# + Cluster: uptrack-pg-cluster --+---------+---------+
# | Member      | Host      | Role   | State | TL | Lag in MB |
# +-----------+----+--------+--------+-----+---------+
# | germany   | ... | Leader | running | ... | 0 |
# | austria   | ... | Replica | running | ... | < 100 MB |
# | india     | ... | Replica | running | ... | < 100 MB |
```

---

## PostgreSQL Configuration Details

### What's Already in node-india-strong-minimal.nix

```nix
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_17_jit;  # PostgreSQL 17.5 with JIT
  enableTCPIP = true;

  settings = {
    max_connections = 100;
    shared_buffers = "256MB";
    effective_cache_size = "1GB";
    work_mem = "16MB";
    maintenance_work_mem = "64MB";
  };

  # Auto-create database
  ensureDatabases = [ "uptrack" ];
  ensureUsers = [{
    name = "uptrack";
    ensureDBOwnership = true;
  }];
};

# SSH starts FIRST (critical for management)
systemd.services.postgresql = {
  after = [ "sshd.service" "network-online.target" ];
  wantedBy = [ "multi-user.target" ];
};
```

### What Needs to Be Added: Patroni Configuration

For now (after flake activation), Patroni will run with defaults. For production:

```nix
services.patroni = {
  enable = true;  # Auto-start

  settings = {
    scope = "uptrack-pg-cluster";
    etcd.hosts = "germany:2379,austria:2379,india-strong:2379";
    postgresql = {
      connect_address = "india-strong-ip:5432";
      replication = {
        username = "replication";
        password = "CHANGE_ME";  # Use agenix for secrets
      };
    };
  };
};
```

---

## 5-Node Architecture Design

### Why PostgreSQL 17.5 JIT on India Strong?

1. **Performance**: JIT compilation speeds up query execution
2. **Replica reads**: Local queries faster for regional monitoring
3. **Cost efficiency**: Oracle Free tier has limited resources
4. **Version consistency**: Matches Germany/Austria (easier replication)

### Why India Strong Must Be Replica (Not Primary)

From `ARCHITECTURE-SUMMARY.md`:

> "PostgreSQL PRIMARY (Germany) ≠ ClickHouse PRIMARY (Austria)"
> **Different nodes** = Isolated failures ✅

India Strong Cannot be Primary because:
1. Primary handles all writes
2. Single point of failure (Oban requires single leader)
3. Germany provides better latency for EU customers
4. Austria has more storage for ClickHouse primary
5. India Strong serves APAC region (local reads via replica)

### Replica Benefits

✅ Automatic failover to Austria/India if Germany fails (30s RTO)
✅ Read-local queries from India Strong (low latency for regional checks)
✅ 3-node consensus (etcd) tolerates 2 node failures
✅ Streaming replication from Germany (near real-time)

---

## Deployment Timeline

### Phase 1: Activate Flake (TODAY)
- [ ] Copy flake to `/home/le/uptrack`
- [ ] Run `nixos-rebuild switch --flake '.#node-india-strong'`
- [ ] Verify PostgreSQL runs
- [ ] Verify SSH available (should take ~10s to boot)

### Phase 2: Configure Patroni (NEXT SESSION)
- [ ] Setup etcd cluster (5-node consensus)
- [ ] Configure Patroni on all 3 PostgreSQL nodes
- [ ] Test failover: Stop Germany, verify Austria promotes
- [ ] Setup HAProxy for connection routing

### Phase 3: Deploy Application (LATER)
- [ ] Deploy Uptrack app to India Strong
- [ ] Configure regional Oban workers
- [ ] Setup ClickHouse replication (if needed for local reads)
- [ ] Monitor cluster performance

### Phase 4: Setup India Weak (FINAL)
- [ ] Second Oracle instance for APAC redundancy
- [ ] App-only + etcd member
- [ ] Completes 5-node architecture

---

## Critical Configuration Files

| File | Purpose | Status |
|------|---------|--------|
| `/Users/le/repos/uptrack/flake.nix` | Declares all nodes | ✅ Complete |
| `/Users/le/repos/uptrack/infra/nixos/node-india-strong-minimal.nix` | India Strong specific | ✅ Ready to activate |
| `/Users/le/repos/uptrack/infra/nixos/common.nix` | Shared across all nodes | ✅ Complete |
| `/Users/le/repos/uptrack/docs/architecture/final-5-node-architecture.md` | Architecture reference | ✅ Reference |

---

## SSH-First Boot Design (Critical!)

System boots in this order:

```
1. systemd multi-user.target startup begins
2. sshd.service starts FIRST ← SSH available ~10 seconds
3. network-online.target reached
4. postgresql.service starts AFTER both above
5. All services ready for management
```

**Why This Matters**: Even if PostgreSQL initialization takes 2-3 minutes (initdb), SSH is available for emergency management.

---

## Commands Reference

### Activate Flake (One-Time)
```bash
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "cd /home/le/uptrack && \
  nixos-rebuild switch --flake '.#node-india-strong' --max-jobs 3"
```

### Check Cluster Status
```bash
# PostgreSQL replication
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "psql -U uptrack -d uptrack -c 'SELECT * FROM pg_stat_replication;'"

# Patroni status
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "patronictl list uptrack-pg-cluster"

# etcd health
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "etcdctl endpoint health --cluster"

# Tailscale mesh
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "tailscale status"
```

### Monitor Build Process
```bash
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "journalctl -u postgresql -f"
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "tail -f /var/log/messages"
```

---

## Lessons Learned

### ✅ What Worked
1. PostgreSQL 17.5 JIT configuration is solid
2. SSH-first boot ordering prevents management lockouts
3. `--max-jobs 3` is optimal for 3 OCPUs + 18GB RAM
4. Simple config (no timeout overrides) is more reliable
5. Flake-based configuration is reproducible

### ⚠️ What to Watch
1. **Configuration sync**: Flake must be copied to system before switching
2. **Module imports**: Verify config loads correctly (check with `nix eval`)
3. **Patroni consensus**: All 3 PostgreSQL nodes must reach each other
4. **etcd quorum**: 5-node etcd requires 3/5 nodes online
5. **Network connectivity**: Tailscale mesh must be healthy

### 🔑 Key Principles for Future Work
1. **Simple > Complex**: Every override should have a reason
2. **SSH first**: Management access is more critical than services
3. **Replica pattern**: Read-local queries for latency
4. **Separated primaries**: Different nodes for failure isolation
5. **Test workflow**: Dry-build → build → switch → reboot

---

## Next Immediate Action

**DO THIS FIRST:**
```bash
# Activate the flake configuration
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "cd /home/le/uptrack && \
  nixos-rebuild build --flake '.#node-india-strong' --max-jobs 3 && \
  nixos-rebuild switch --flake '.#node-india-strong' && \
  reboot"

# Wait ~30 seconds, then verify
ssh -i ~/.ssh/id_ed25519 root@152.67.179.42 "systemctl is-active postgresql && echo 'PostgreSQL running!'"
```

This will:
1. Build the flake configuration
2. Switch to it for next boot
3. Reboot to activate
4. PostgreSQL should auto-start
5. Patroni should auto-start and begin replication from Germany

---

**Status**: Ready for immediate flake activation
**Owner**: System needs root SSH access (currently working)
**Timeline**: ~30 minutes for Phase 1 activation
**Risk Level**: Low (auto-rollback protection enabled)

