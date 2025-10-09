# ✅ NixOS Deployment Setup Complete

I've created a complete NixOS deployment configuration for Uptrack based on the proven Terra project pattern.

## What's Been Created

### Core Configuration Files

1. **`flake.nix`** - Main Nix flake with:
   - Colmena deployment configuration for all 3 nodes
   - nixos-anywhere installation apps
   - Development shell with all tools
   - Both x86_64-linux and aarch64-darwin (Mac) support

2. **`infra/nixos/common.nix`** - Shared configuration:
   - Boot loader setup
   - SSH configuration with your public key
   - Firewall settings
   - System packages (vim, git, htop, etc.)
   - Nix settings with flakes enabled

3. **`infra/nixos/disko.nix`** - Disk partitioning:
   - GPT partition table
   - EFI boot partition
   - 4GB swap
   - ext4 root filesystem

4. **`infra/nixos/node-{a,b,c}.nix`** - Node-specific configs:
   - Hostnames
   - Firewall rules
   - Region identification

5. **`infra/nixos/secrets/`** - Agenix secrets management:
   - `secrets.nix` - Public key configuration
   - `uptrack-env.example` - Environment variables template
   - `.gitignore` - Protects unencrypted secrets
   - `README.md` - Complete secrets workflow guide

6. **`nixos-deploy.sh`** - Helper script with commands for:
   - Installing NixOS on each node
   - Deploying configurations
   - SSH access
   - Viewing logs
   - Checking service status
   - Managing secrets

7. **`docs/nixos-deployment-guide.md`** - Comprehensive guide covering:
   - Architecture overview
   - Step-by-step deployment process
   - Troubleshooting
   - Comparison with Terra project

## How This Works

### Initial Installation (One-time per server)

```bash
./nixos-deploy.sh install-node-c
```

This:
1. Uses `nixos-anywhere` to SSH into server
2. Wipes disk and partitions according to `disko.nix`
3. Installs NixOS with your configuration
4. Reboots with your SSH key configured

### Setup Secrets

```bash
# Generate random secrets
./nixos-deploy.sh generate-keys

# Create and encrypt secrets
cd infra/nixos/secrets
cp uptrack-env.example uptrack-env
vim uptrack-env  # Fill in values

# Get server SSH host key after install
ssh root@147.93.146.35 cat /etc/ssh/ssh_host_ed25519_key.pub

# Add to secrets.nix, then encrypt
nix develop --command agenix -e uptrack-env.age
```

### Ongoing Deployments

```bash
./nixos-deploy.sh deploy-node-c     # Deploy to one node
./nixos-deploy.sh deploy-all        # Deploy to all nodes
```

This:
1. Builds NixOS configuration
2. Pushes to server
3. Activates new configuration
4. Restarts changed services

## Node Configuration

- **Node A** (167.235.243.206) - Hetzner - Primary with HAProxy
- **Node B** (185.237.12.64) - Contabo - Secondary
- **Node C** (147.93.146.35) - Contabo - Tertiary

Each will run:
- Uptrack Phoenix app
- PostgreSQL with TimescaleDB
- ClickHouse

## What's Still Needed

To complete the deployment, you need to create service configurations:

### Required Service Files

1. `infra/nixos/services/uptrack-app.nix` - Phoenix application
2. `infra/nixos/services/postgres.nix` - PostgreSQL setup
3. `infra/nixos/services/timescaledb.nix` - TimescaleDB extension
4. `infra/nixos/services/clickhouse.nix` - ClickHouse database
5. `infra/nixos/services/haproxy.nix` - Load balancer (Node A only)
6. `infra/nixos/packages/uptrack-app.nix` - Phoenix release build

These will define how each service is installed, configured, and managed by systemd.

## Key Advantages

✅ **Declarative** - Everything in code, version controlled
✅ **Reproducible** - Same config = same result every time  
✅ **Atomic Updates** - Can rollback instantly if issues
✅ **Encrypted Secrets** - Agenix for secure secret management
✅ **No Manual Steps** - Fully automated deployment
✅ **Proven Pattern** - Same as Terra (already working in production)

## Next Steps

1. **Test the Infrastructure** (optional):
   ```bash
   nix flake check  # Verify flake is valid
   ```

2. **Create Service Configurations**: Implement the service .nix files

3. **Setup Secrets**: Fill in real values in uptrack-env

4. **Test on Node C**:
   ```bash
   ./nixos-deploy.sh install-node-c
   ./nixos-deploy.sh deploy-node-c
   ```

5. **Validate & Monitor**:
   ```bash
   ./nixos-deploy.sh logs-node-c
   ./nixos-deploy.sh status-node-c
   ```

6. **Repeat for Nodes B & A** once Node C is validated

## Quick Reference

```bash
# Installation (WIPES DISK!)
./nixos-deploy.sh install-node-c

# Deployment
./nixos-deploy.sh deploy-node-c
./nixos-deploy.sh deploy-all

# Management
./nixos-deploy.sh ssh-node-c
./nixos-deploy.sh logs-node-c
./nixos-deploy.sh status-node-c

# Secrets
./nixos-deploy.sh setup-secrets
./nixos-deploy.sh generate-keys
./nixos-deploy.sh rekey

# Utilities
./nixos-deploy.sh build
./nixos-deploy.sh check
```

## Documentation

- **Deployment Guide**: `docs/nixos-deployment-guide.md`
- **Secrets Guide**: `infra/nixos/secrets/README.md`
- **Helper Script**: `./nixos-deploy.sh help`

## Comparison with Current Setup

| Current | New NixOS |
|---------|-----------|
| Manual SSH setup | Automated with nixos-anywhere |
| Docker containers | Native systemd services |
| Manual secrets | Encrypted with agenix |
| Manual updates | Declarative with Colmena |
| Tailscale only | Public IPs + proper networking |
| Hard to reproduce | Fully reproducible |

---

**Ready to proceed!** The infrastructure is set up following Terra's proven pattern. Next step is to create the service configurations and test on Node C.
