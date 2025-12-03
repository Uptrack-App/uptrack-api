# Node Inventory

## Current Nodes (As of 2025-10-30)

### EU Nodes (Hostkey Italy)

#### eu-a (Future Primary)
- **Provider:** Hostkey Italy
- **Hostname:** hostkey22275
- **Plan:** v2-mini
- **Public IP:** REMOVED_IP
- **Gateway:** 194.180.207.1
- **Netmask:** 255.255.255.0
- **Specs:** 4 vCPU, 8GB RAM, 120GB NVMe
- **Tailscale IP:** 100.64.1.1 (to be assigned)
- **Services:** etcd, PostgreSQL Primary, vmstorage1, vminsert1
- **SSH:** `ssh root@REMOVED_IP`
- **Initial Password:** sEGsqcEi4L (change after SSH key setup!)
- **Status:** Active (Due in 31 days)

#### eu-b (Future Replica)
- **Provider:** Hostkey Italy
- **Hostname:** hostkey28628
- **Plan:** v2-mini
- **Public IP:** REMOVED_IP
- **Gateway:** 194.180.207.1
- **Netmask:** 255.255.255.0
- **Specs:** 4 vCPU, 8GB RAM, 120GB NVMe
- **Tailscale IP:** 100.64.1.2 (to be assigned)
- **Services:** etcd, PostgreSQL Replica, vmstorage2, vmselect1
- **SSH:** `ssh root@REMOVED_IP`
- **Initial Password:** W3ZuN9bg6m (change after SSH key setup!)
- **Status:** Active (Due in 31 days)

#### eu-c (Future Witness)
- **Provider:** Hostkey Italy
- **Hostname:** hostkey48628
- **Plan:** v2-mini
- **Public IP:** REMOVED_IP
- **Gateway:** 194.180.207.1
- **Netmask:** 255.255.255.0
- **Specs:** 4 vCPU, 8GB RAM, 120GB NVMe
- **Tailscale IP:** 100.64.1.3 (to be assigned)
- **Services:** etcd, PostgreSQL Witness, vmstorage3, vminsert2, vmselect2
- **SSH:** `ssh root@REMOVED_IP`
- **Initial Password:** jA-gMAiBOm (change after SSH key setup!)
- **Status:** Active (Due in 31 days)

### India Nodes (Oracle Cloud Free Tier)

#### india-s (Strong - Primary Asia)
- **Provider:** Oracle Cloud (Free Tier)
- **Instance:** VM.Standard.A1.Flex
- **Public IP:** 152.67.179.42
- **Specs:** 3 vCPU (ARM64), 18GB RAM, 46GB SSD
- **Tailscale IP:** 100.64.1.10 (to be assigned)
- **Services:** PostgreSQL Async Replica, vmselect3, Prometheus
- **SSH:** `ssh -i ~/.ssh/id_ed25519 le@152.67.179.42`
- **Status:** Active (NixOS)

#### india-w (Weak - Backups & Logs)
- **Provider:** Oracle Cloud (Free Tier)
- **Instance:** VM.Standard.E2.1.Micro
- **Public IP:** REMOVED_IP
- **Specs:** 1 vCPU (ARM64), 6GB RAM, ~40GB SSD
- **Tailscale IP:** 100.64.1.11 (to be assigned)
- **Services:** Backups (WAL-G, vmbackup), Loki, Alertmanager
- **SSH:** `ssh root@REMOVED_IP` or `ssh ubuntu@REMOVED_IP`
- **Status:** Active

## Network Details

### Bandwidth & Transfer
- **Hostkey Italy:** 1 Gbit/s, 3TB/month per node
- **Oracle Cloud:** Variable (typically 1-10 Gbps)

### Expected Latency
- EU internal (Italy): <20ms
- EU to India: ~150ms
- India internal: <10ms

## Access Credentials

**Security Note:** All credentials stored in Bitwarden Secret Manager (future) or agenix/sops-nix (current).

### SSH Keys
- **EU nodes:** [TO BE DOCUMENTED]
- **india-s:** `~/.ssh/id_ed25519`
- **india-w:** [TO BE DOCUMENTED]

### Tailscale
- **Account:** [TO BE CREATED]
- **Tailnet:** [TO BE CREATED]
- **Auth key:** [Ephemeral, one-time use]

## Maintenance Windows

- **Preferred:** Tuesday/Thursday 02:00-04:00 UTC (low traffic)
- **Emergency:** Any time (with user notification)

## Future Migration Plan

**Target:** Replace Hostkey Italy → Netcup Austria (Phase 4)
- **Reason:** Better specs, German data center, similar latency
- **Method:** Zero-downtime migration via Tailscale IP swap
- **Timeline:** After Phase 3 complete (3-4 weeks)
