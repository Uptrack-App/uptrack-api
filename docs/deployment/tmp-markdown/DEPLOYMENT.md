# Uptrack Deployment Guide

Complete guide for deploying Uptrack to production with 3-node HA setup.

## 🏗️ Architecture Overview

```
           Cloudflare (uptrack.app)
                    ↓
    ┌───────────────┼───────────────┐
    │               │               │
 Node A          Node B          Node C
(us-east)    (eu-central)   (ap-southeast)
    │               │               │
    ├─ Phoenix      ├─ Phoenix      ├─ Phoenix
    ├─ Postgres     ├─ Postgres     ├─ ClickHouse
    ├─ Patroni      ├─ Patroni      ├─ etcd
    ├─ etcd         ├─ etcd         ├─ HAProxy
    ├─ HAProxy      ├─ HAProxy      └─ Oban (regional)
    └─ Oban (regional)
```

**Key Features:**
- ✅ **High Availability** - Automatic Postgres failover with Patroni
- ✅ **Multi-Region** - Oban workers in 3 geographic regions
- ✅ **Secure** - Tailscale private network, no public DB ports
- ✅ **Scalable** - etcd consensus, ClickHouse analytics
- ✅ **Automated** - NixOS + Colmena declarative deployment

---

## 📋 Prerequisites

### Local Machine
- **Nix** with flakes enabled
- **SSH** key for server access
- **Tailscale** account (free tier works)

### VPS Servers (3x)
- **Provider**: Hetzner, DigitalOcean, Linode, etc.
- **Specs**: 2 vCPU, 4GB RAM minimum (per node)
- **OS**: NixOS 24.11 (or fresh install)
- **Regions**: 3 different geographic locations

### Domain
- **Domain**: `uptrack.app` (registered and added to Cloudflare)

---

## 🚀 Deployment Steps

### Step 1: Install Nix (if not installed)

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Step 2: Clone Repository

```bash
git clone https://github.com/yourusername/uptrack.git
cd uptrack
```

### Step 3: Enter Development Environment

```bash
nix develop
```

This installs Colmena, agenix, and other deployment tools.

### Step 4: Provision VPS Instances

Provision 3 VPS instances in different regions:

| Node | Region | Provider Example |
|------|--------|-----------------|
| A | us-east | New York, USA |
| B | eu-central | Frankfurt, Germany |
| C | ap-southeast | Singapore |

Note down the **public IP addresses**.

### Step 5: Update Flake with IPs

Edit `flake.nix` and replace placeholder IPs:

```nix
# Line 60
targetHost = "YOUR_NODE_A_IP";  # e.g., "123.456.78.90"

# Line 70
targetHost = "YOUR_NODE_B_IP";

# Line 80
targetHost = "YOUR_NODE_C_IP";
```

### Step 6: Setup Tailscale

#### 6.1 Get Tailscale Auth Key

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate a **reusable auth key**
3. Copy the key

#### 6.2 Install Tailscale on All Nodes

```bash
export NODE_A_IP=YOUR_NODE_A_IP
export NODE_B_IP=YOUR_NODE_B_IP
export NODE_C_IP=YOUR_NODE_C_IP

# Install and setup
for ip in $NODE_A_IP $NODE_B_IP $NODE_C_IP; do
  ssh root@$ip "curl -fsSL https://tailscale.com/install.sh | sh"
  ssh root@$ip "tailscale up --authkey=YOUR_AUTH_KEY --accept-routes"
done
```

#### 6.3 Get Tailscale IPs

```bash
ssh root@$NODE_A_IP "tailscale ip -4"  # e.g., 100.64.0.1
ssh root@$NODE_B_IP "tailscale ip -4"  # e.g., 100.64.0.2
ssh root@$NODE_C_IP "tailscale ip -4"  # e.g., 100.64.0.3
```

#### 6.4 Update Tailscale IPs in Configs

Replace `100.64.0.x` placeholders in:
- `infra/nixos/services/etcd.nix`
- `infra/nixos/services/patroni.nix`
- `infra/nixos/services/haproxy.nix`
- `infra/nixos/services/uptrack-app.nix`

### Step 7: Configure Secrets

#### 7.1 Generate Secrets

```bash
./nixos-deploy.sh generate-keys
```

#### 7.2 Create Secret File

```bash
cp infra/nixos/secrets/uptrack-env.example infra/nixos/secrets/uptrack-env
```

Edit `infra/nixos/secrets/uptrack-env` and paste generated secrets.

#### 7.3 Get Server SSH Host Keys

```bash
ssh root@$NODE_A_IP "cat /etc/ssh/ssh_host_ed25519_key.pub"
ssh root@$NODE_B_IP "cat /etc/ssh/ssh_host_ed25519_key.pub"
ssh root@$NODE_C_IP "cat /etc/ssh/ssh_host_ed25519_key.pub"
```

Add these keys to `infra/nixos/secrets/secrets.nix`.

#### 7.4 Encrypt Secrets

```bash
nix develop
agenix -e infra/nixos/secrets/uptrack-env.age
```

### Step 8: Configure Cloudflare DNS

1. Add `uptrack.app` to Cloudflare
2. Create 3 A records (proxied/orange cloud):
   ```
   uptrack.app → NODE_A_IP
   uptrack.app → NODE_B_IP
   uptrack.app → NODE_C_IP
   ```

### Step 9: Deploy!

```bash
./nixos-deploy.sh deploy-all
```

This will:
- Build NixOS configurations
- Deploy to all 3 nodes simultaneously
- Start all services (Patroni, etcd, HAProxy, Phoenix, ClickHouse)
- Run database migrations
- Configure HTTPS certificates

**Deployment takes ~10-15 minutes.**

### Step 10: Verify Deployment

```bash
# Check service status
./nixos-deploy.sh status-all

# Check health endpoints
./nixos-deploy.sh health-check

# View logs
./nixos-deploy.sh logs-all
```

Visit `https://uptrack.app` - you should see your app! 🎉

---

## 🔧 Post-Deployment

### Initialize Database

SSH into Node A and run schema setup:

```bash
ssh root@$NODE_A_IP
psql -U postgres -d uptrack_prod -f /path/to/deploy/sql/00-init-schemas.sql
psql -U postgres -d uptrack_prod -f /path/to/deploy/sql/01-timescaledb-setup.sql
```

### Verify Patroni Cluster

```bash
ssh root@$NODE_A_IP
patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster
```

Expected output:
```
+ Cluster: uptrack-pg-cluster ----+---------+----+-----------+
| Member | Host        | Role    | State   | TL | Lag in MB |
+--------+-------------+---------+---------+----+-----------+
| node-a | 100.64.0.1  | Leader  | running |  1 |           |
| node-b | 100.64.0.2  | Replica | running |  1 |         0 |
+--------+-------------+---------+---------+----+-----------+
```

### Test Failover

Kill Node A's Patroni and watch Node B promote automatically:

```bash
ssh root@$NODE_A_IP "systemctl stop patroni"
# Wait 30 seconds
ssh root@$NODE_B_IP "patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster"
# Node B should now be Leader
```

Restart Node A:
```bash
ssh root@$NODE_A_IP "systemctl start patroni"
```

---

## 📊 Monitoring

### Health Checks

```bash
curl https://uptrack.app/healthz | jq .
```

Expected response:
```json
{
  "status": "healthy",
  "checks": {
    "database": "ok",
    "oban": "ok",
    "node_region": "us-east",
    "node_name": "node-a"
  },
  "timestamp": "2025-10-09T10:00:00Z"
}
```

### HAProxy Stats

Access on each node:
```bash
ssh root@$NODE_A_IP -L 8404:127.0.0.1:8404
```

Visit: http://localhost:8404/stats
- Username: `admin`
- Password: (from HAProxy config)

### Logs

```bash
# View all logs
./nixos-deploy.sh logs-all

# SSH into specific node
./nixos-deploy.sh ssh-a

# View specific service
ssh root@$NODE_A_IP "journalctl -u uptrack-app -f"
```

---

## 🔄 Ongoing Deployments

### Deploy Code Changes

```bash
# Build and deploy to all nodes
./nixos-deploy.sh deploy-all

# Or deploy to single node (rolling deploy)
./nixos-deploy.sh deploy-node-a
sleep 30
./nixos-deploy.sh deploy-node-b
sleep 30
./nixos-deploy.sh deploy-node-c
```

### Update Secrets

```bash
nix develop
agenix -e infra/nixos/secrets/uptrack-env.age
# Make changes
# Save and exit
./nixos-deploy.sh deploy-all
```

### Database Migrations

Migrations run automatically on deploy. To run manually:

```bash
ssh root@$NODE_A_IP
/nix/store/.../bin/uptrack eval "Uptrack.Release.migrate()"
```

---

## 🆘 Troubleshooting

### Deployment Fails

```bash
# Check flake syntax
nix flake check

# Build locally without deploying
./nixos-deploy.sh build

# View detailed logs
colmena apply --verbose
```

### Service Won't Start

```bash
# Check status
systemctl status uptrack-app

# View logs
journalctl -u uptrack-app -n 100

# Common issues:
# 1. Database not ready
systemctl status patroni

# 2. Tailscale not connected
tailscale status

# 3. Missing secrets
ls -la /run/agenix/
```

### Patroni Split-Brain

```bash
# Check etcd cluster
etcdctl endpoint health --cluster

# Reinitialize node (WARNING: deletes data)
patronictl reinit uptrack-pg-cluster node-b
```

### ClickHouse Not Receiving Data

```bash
# Check spool directory
ssh root@$NODE_C_IP "ls -lh /var/lib/uptrack-app/spool/"

# Manually flush
systemctl start clickhouse-spool-flush.service

# Check ClickHouse logs
journalctl -u clickhouse -f
```

---

## 📖 Architecture Details

### Network Topology

```
Public Internet
       ↓
Cloudflare (DDoS protection, CDN, WAF)
       ↓
HAProxy :443 (on each node)
       ↓
Phoenix :4000 (local)
       ↓
       ├─ HAProxy :6432 (local DB proxy)
       │      ↓
       │  Patroni REST API :8008 (which node is primary?)
       │      ↓
       │  Postgres :5432 (via Tailscale 100.x.x.x)
       │
       └─ ClickHouse :8123 (via Tailscale 100.64.0.3)
```

### Data Flow

1. **User Request** → Cloudflare → Random node (A, B, or C)
2. **App Query** → Local HAProxy :6432 → Asks Patroni who's primary → Connects to primary via Tailscale
3. **Monitor Check** → Oban job on node matching region → Writes to ClickHouse via Tailscale

### Failure Scenarios

| Failure | Impact | Recovery Time |
|---------|--------|---------------|
| Node A dies | Users route to B/C | 0s (instant) |
| Postgres primary dies | Patroni promotes replica | ≤30s |
| ClickHouse dies | Data spools to disk | 0s (queued) |
| etcd node dies | Cluster continues (quorum) | 0s |
| Entire region offline | Traffic routes to other 2 regions | 0s |

---

## 🎯 Next Steps

1. **Set up monitoring**: Prometheus + Grafana
2. **Configure backups**: Automated pgBackRest to S3
3. **Add staging environment**: Single-node staging deploy
4. **CI/CD pipeline**: GitHub Actions auto-deploy
5. **Load testing**: Verify HA under load
6. **Documentation**: Internal runbooks

---

## 📚 Resources

- [Patroni Documentation](https://patroni.readthedocs.io/)
- [Colmena Deployment](https://colmena.cli.rs/)
- [Agenix Secrets Management](https://github.com/ryantm/agenix)
- [Tailscale Guide](https://tailscale.com/kb/)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)

---

## 🙏 Support

If you encounter issues:
1. Check logs: `./nixos-deploy.sh logs-all`
2. Verify Tailscale: `tailscale status`
3. Check Patroni: `patronictl list uptrack-pg-cluster`
4. Review deployment plan: `docs/deployment-plan.md`

**Deployment complete! Enjoy your HA production setup!** 🚀
