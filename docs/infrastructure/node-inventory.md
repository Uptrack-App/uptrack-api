# Node Inventory

## Current Nodes (As of 2026-01-28)

### Netcup Nuremberg Nodes (EU Compute)

#### nbg1 (Coordinator Primary + Phoenix API)
- **Provider:** Netcup (Nuremberg, Germany)
- **Public IP:** 152.53.181.117
- **Tailscale IP:** 100.64.1.1 (static)
- **Services:** Phoenix API, PostgreSQL Coordinator Primary, Patroni (coordinator), cloudflared, etcd (1/3), vminsert, vmselect, vmagent
- **SSH:** `ssh -i ~/.ssh/uptrack root@152.53.181.117`
- **SSH (Tailscale):** `ssh -i ~/.ssh/uptrack root@100.64.1.1`
- **Status:** Active, Tailscale connected (direct, no relay)

#### nbg2 (Coordinator Standby + Phoenix API)
- **Provider:** Netcup (Nuremberg, Germany)
- **Public IP:** 152.53.183.208
- **Tailscale IP:** 100.64.1.2 (static)
- **Services:** Phoenix API, PostgreSQL Coordinator Standby, Patroni (coordinator), cloudflared, etcd (2/3), vminsert, vmselect, vmagent
- **SSH:** `ssh -i ~/.ssh/uptrack root@152.53.183.208`
- **SSH (Tailscale):** `ssh -i ~/.ssh/uptrack root@100.64.1.2`
- **Status:** Active, Tailscale connected (direct, no relay)

#### nbg3 (Citus Worker Primary)
- **Provider:** Netcup (Nuremberg, Germany)
- **Public IP:** 152.53.180.51
- **Tailscale IP:** 100.64.1.3 (static)
- **Services:** PostgreSQL Worker Primary (all shards), Patroni (worker), etcd (3/3), vmstorage, vmselect
- **SSH:** `ssh -i ~/.ssh/uptrack root@152.53.180.51`
- **SSH (Tailscale):** `ssh -i ~/.ssh/uptrack root@100.64.1.3`
- **Status:** Active, Tailscale connected (direct, no relay)

#### nbg4 (Citus Worker Standby)
- **Provider:** Netcup (Nuremberg, Germany)
- **Public IP:** 159.195.56.242
- **Tailscale IP:** 100.64.1.4 (static)
- **Services:** PostgreSQL Worker Standby, Patroni (worker), vmstorage
- **SSH:** `ssh -i ~/.ssh/uptrack root@159.195.56.242`
- **SSH (Tailscale):** `ssh -i ~/.ssh/uptrack root@100.64.1.4`
- **Status:** Active, Tailscale connected (direct, no relay)

### HostHatch Amsterdam (EU Storage)

#### storage-1 (Storage Node)
- **Provider:** HostHatch (Amsterdam, Netherlands)
- **Public IP:** [TBD]
- **Tailscale IP:** [Pending deployment] (target: 100.64.2.1)
- **Services:** vmstorage (HA node 3/3, dedicated 1TB NVMe)
- **SSH:** `ssh -i ~/.ssh/uptrack root@<ip>`
- **Status:** Pending Tailscale deployment

### Oracle Cloud India (DR)

#### india-rworker (Backups & Logs)
- **Provider:** Oracle Cloud (Free Tier)
- **Instance:** VM.Standard.E2.1.Micro
- **Public IP:** 144.24.150.48
- **Specs:** 1 vCPU (aarch64), 6GB RAM, ~40GB SSD
- **Tailscale IP:** 100.64.1.11 (static)
- **Services:** Backups (PG WAL + VM)
- **SSH:** `ssh root@144.24.150.48`
- **SSH (Tailscale):** `ssh root@100.64.1.11`
- **Status:** Active, Tailscale connected (direct, no relay)

## Tailscale Node Summary

| Node | Public IP | Tailscale IP | Provider | Location | Arch |
|------|----------|-------------|----------|----------|------|
| nbg1 | 152.53.181.117 | 100.64.1.1 | Netcup G12 Pro | Nuremberg, DE | x86_64 |
| nbg2 | 152.53.183.208 | 100.64.1.2 | Netcup G12 Pro | Nuremberg, DE | x86_64 |
| nbg3 | 152.53.180.51 | 100.64.1.3 | Netcup G12 Pro | Nuremberg, DE | x86_64 |
| nbg4 | 159.195.56.242 | 100.64.1.4 | Netcup G12 Pro | Nuremberg, DE | x86_64 |
| india-rworker | 144.24.150.48 | 100.64.1.11 | Oracle Free Tier | Hyderabad, IN | aarch64 |

## Tailscale IP Scheme

| Layer | IP Range | Description |
|-------|----------|-------------|
| Compute | 100.64.1.1-4 | Netcup Nuremberg nodes (nbg1-4) |
| Storage | 100.64.2.x | HostHatch Amsterdam (storage-1) - pending |
| Regional | 100.64.1.11 | Oracle Cloud India (india-rworker) |

**All static IPs assigned and verified as of 2026-01-28.** Key expiry disabled on all nodes.

## Network Details

### Tailscale Connectivity Matrix (Verified 2026-01-28)

All connections are **DIRECT** (no DERP relay). 0% packet loss.

| Route | Latency | Connection |
|-------|---------|------------|
| nbg1 <-> nbg2 | 1-13ms | Direct |
| nbg1 <-> nbg3 | 1-13ms | Direct |
| nbg1 <-> nbg4 | 1-13ms | Direct |
| nbg2 <-> nbg3 | 1-13ms | Direct |
| nbg2 <-> nbg4 | 1-13ms | Direct |
| nbg3 <-> nbg4 | 1-13ms | Direct |
| nbg* <-> india-rworker | 165-440ms | Direct |

### Latency Summary
- **EU internal (nbg<->nbg):** 1-13ms direct
- **Cross-region (nbg<->india):** 165-440ms direct
- **Nuremberg to Amsterdam:** 5-10ms (estimated, storage-1 pending)

### Tailscale
- **Account:** hoangbytes@gmail.com
- **Tailnet:** tail0b6319.ts.net
- **Version:** 1.82.5
- **Tags:** tag:infrastructure (all nodes)
- **Key expiry:** Disabled on all nodes
- **Auth key:** Reusable, non-ephemeral (generated 2026-01-28)

## Access Credentials

**Security Note:** All credentials stored via agenix in `infra/nixos/secrets/`.

### SSH Keys
- **All nodes:** `~/.ssh/uptrack`
- **Public key:** `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOlnOlGCkDNCBadzikbIMVBDe1jJQTDXeqZYc8e6SYIX le@le-arm64`

### SSH Quick Reference (Tailscale)

```bash
# Nuremberg nodes (via Tailscale mesh)
ssh -i ~/.ssh/uptrack root@100.64.1.1   # nbg1
ssh -i ~/.ssh/uptrack root@100.64.1.2   # nbg2
ssh -i ~/.ssh/uptrack root@100.64.1.3   # nbg3
ssh -i ~/.ssh/uptrack root@100.64.1.4   # nbg4

# India node (via Tailscale mesh)
ssh root@100.64.1.11                     # india-rworker
```

### SSH Quick Reference (Public IP)

```bash
ssh -i ~/.ssh/uptrack root@152.53.181.117  # nbg1
ssh -i ~/.ssh/uptrack root@152.53.183.208  # nbg2
ssh -i ~/.ssh/uptrack root@152.53.180.51   # nbg3
ssh -i ~/.ssh/uptrack root@159.195.56.242  # nbg4
ssh root@144.24.150.48                      # india-rworker
```

### SSH Config (~/.ssh/config)
```
Host 152.53.181.117
  User root
  IdentityFile ~/.ssh/uptrack

Host 152.53.183.208
  User root
  IdentityFile ~/.ssh/uptrack

Host 152.53.180.51
  User root
  IdentityFile ~/.ssh/uptrack

Host 159.195.56.242
  User root
  IdentityFile ~/.ssh/uptrack

Host 100.64.1.1
  User root
  IdentityFile ~/.ssh/uptrack

Host 100.64.1.2
  User root
  IdentityFile ~/.ssh/uptrack

Host 100.64.1.3
  User root
  IdentityFile ~/.ssh/uptrack

Host 100.64.1.4
  User root
  IdentityFile ~/.ssh/uptrack
```

## Deployment Commands

```bash
# Deploy to single node
colmena apply --on nbg1

# Deploy to all Nuremberg nodes
colmena apply --on 'nbg*'

# Check Tailscale status
ssh root@152.53.181.117 "tailscale status"
```

## Maintenance Windows

- **Preferred:** Tuesday/Thursday 02:00-04:00 UTC (low traffic)
- **Emergency:** Any time (with user notification)
