# Uptrack NixOS Deployment Guide

This guide covers the complete NixOS deployment setup for Uptrack using Colmena, nixos-anywhere, disko, and agenix - following the proven pattern from the Terra project.

## Architecture

### Infrastructure

- **Node A** (Hetzner - 167.235.243.206): Primary node with HAProxy load balancer
- **Node B** (Contabo - 185.237.12.64): Secondary node
- **Node C** (Contabo - 147.93.146.35): Tertiary node

Each node runs:
- Phoenix/Elixir application
- PostgreSQL with TimescaleDB
- ClickHouse for time-series data

### Key Technologies

- **Colmena**: Declarative NixOS deployment tool (like Terraform for NixOS)
- **nixos-anywhere**: Automated remote NixOS installation
- **Disko**: Declarative disk partitioning
- **Agenix**: Age-based secrets management

## Prerequisites

1. **Nix with Flakes** installed:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **SSH Key** (ed25519):
   ```bash
   # Generate if you don't have one
   ssh-keygen -t ed25519 -C "your@email.com"
   ```

3. **Server Access**: Root access to all three servers via SSH

## Quick Start

### 1. Setup Secrets

```bash
# Generate random secrets
./nixos-deploy.sh generate-keys

# Create secrets file
cd infra/nixos/secrets
cp uptrack-env.example uptrack-env
vim uptrack-env  # Fill in real values
```

### 2. Install NixOS on Node C (Example)

```bash
# This will WIPE the server and install NixOS
./nixos-deploy.sh install-node-c
```

**What happens:**
1. `nixos-anywhere` SSHs into the server
2. Partitions disk according to `infra/nixos/disko.nix`
3. Installs NixOS with configuration from `flake.nix`
4. Server reboots automatically
5. Your SSH key is configured for passwordless access

### 3. Add Server SSH Host Key

After installation, get the server's SSH host key:

```bash
ssh root@147.93.146.35 cat /etc/ssh/ssh_host_ed25519_key.pub
```

Add it to `infra/nixos/secrets/secrets.nix`:

```nix
nodeCKey = [
  "ssh-ed25519 AAAA... root@uptrack-node-c"
];
```

### 4. Encrypt Secrets

```bash
./nixos-deploy.sh rekey
```

This encrypts `uptrack-env` using both your admin key and the server's host key.

### 5. Deploy Application

```bash
./nixos-deploy.sh deploy-node-c
```

**What happens:**
1. Colmena builds the NixOS configuration
2. Builds on the target server (saves bandwidth)
3. Activates the new configuration
4. Starts all services (PostgreSQL, ClickHouse, Phoenix app, HAProxy)

## Deployment Commands

### Installation (One-time, WIPES DISK)

```bash
./nixos-deploy.sh install-node-a  # Hetzner
./nixos-deploy.sh install-node-b  # Contabo
./nixos-deploy.sh install-node-c  # Contabo
```

### Ongoing Deployments

```bash
./nixos-deploy.sh deploy-all       # Deploy to all nodes
./nixos-deploy.sh deploy-node-a    # Deploy to Node A only
./nixos-deploy.sh deploy-node-b    # Deploy to Node B only
./nixos-deploy.sh deploy-node-c    # Deploy to Node C only
```

### Monitoring & Debugging

```bash
# SSH into nodes
./nixos-deploy.sh ssh-node-c

# View logs
./nixos-deploy.sh logs-node-c

# Check service status
./nixos-deploy.sh status-node-c
```

## File Structure

```
uptrack/
├── flake.nix                          # Main Nix flake with Colmena config
├── nixos-deploy.sh                    # Deployment helper script
├── infra/nixos/
│   ├── common.nix                     # Shared configuration
│   ├── disko.nix                      # Disk partitioning
│   ├── node-a.nix                     # Node A specific config
│   ├── node-b.nix                     # Node B specific config
│   ├── node-c.nix                     # Node C specific config
│   ├── services/
│   │   ├── uptrack-app.nix            # Phoenix application service
│   │   ├── postgres.nix               # PostgreSQL service
│   │   ├── timescaledb.nix            # TimescaleDB extension
│   │   ├── clickhouse.nix             # ClickHouse service
│   │   └── haproxy.nix                # HAProxy load balancer (Node A only)
│   └── secrets/
│       ├── secrets.nix                # Agenix public keys config
│       ├── uptrack-env.example        # Environment variables template
│       ├── uptrack-env                # Real secrets (gitignored)
│       └── uptrack-env.age            # Encrypted secrets (committed)
```

## Workflow Patterns

### Making Configuration Changes

1. Edit files in `infra/nixos/`
2. Build locally to test:
   ```bash
   ./nixos-deploy.sh build
   ```
3. Deploy:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

### Updating Secrets

1. Edit encrypted file:
   ```bash
   cd infra/nixos/secrets
   nix develop --command agenix -e uptrack-env.age
   ```
2. Save and exit
3. Deploy changes:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

### Rolling Back

NixOS keeps previous generations. To rollback:

```bash
ssh root@147.93.146.35
nixos-rebuild --rollback switch
```

### Adding a New Service

1. Create service file: `infra/nixos/services/myservice.nix`
2. Add import to `flake.nix`:
   ```nix
   imports = commonModules ++ [
     # ...
     ./infra/nixos/services/myservice.nix
   ];
   ```
3. Deploy:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

## Differences from Current Setup

### ✅ Advantages over Manual Setup

1. **Declarative**: Everything in code, version controlled
2. **Reproducible**: Same config = same result every time
3. **Atomic**: Updates are atomic, can rollback instantly
4. **Secrets Management**: Encrypted secrets with agenix
5. **No Manual Steps**: No SSH key copying, no manual service setup
6. **Build on Target**: Saves bandwidth, faster deploys
7. **Proven Pattern**: Same as Terra project (already working)

### Migration Path

**Current:** Manual SSH, Tailscale, Docker, manual secrets
**New:** NixOS with Colmena, native services, encrypted secrets

**Migration steps:**
1. Start with Node C (test node)
2. Validate everything works
3. Move to Node B, then Node A
4. Update DNS/load balancer

## Troubleshooting

### "No identities found" when encrypting

Your SSH key doesn't match `secrets.nix`. Make sure:
```bash
cat ~/.ssh/id_ed25519.pub
# Should match the key in infra/nixos/secrets/secrets.nix
```

### Server can't decrypt secrets

1. Get server's SSH host key:
   ```bash
   ssh root@147.93.146.35 cat /etc/ssh/ssh_host_ed25519_key.pub
   ```
2. Add to `secrets.nix`
3. Re-encrypt:
   ```bash
   ./nixos-deploy.sh rekey
   ```
4. Redeploy:
   ```bash
   ./nixos-deploy.sh deploy-node-c
   ```

### Build fails

Check the flake:
```bash
./nixos-deploy.sh check
```

Build locally to see errors:
```bash
nix develop --command colmena build
```

### Service won't start

Check logs on the server:
```bash
./nixos-deploy.sh ssh-node-c
journalctl -u uptrack-app -f
```

Check service status:
```bash
./nixos-deploy.sh status-node-c
```

## Next Steps

1. **Complete Service Configurations**: Finish implementing service .nix files
2. **Build Phoenix Release**: Create Nix derivation for Uptrack app
3. **Test Node C**: Full deployment test on Node C
4. **Migrate Nodes B & A**: Once C is validated
5. **Setup Monitoring**: Add Prometheus/Grafana configs
6. **CI/CD Integration**: Automate deployments from GitHub

## Comparison with Terra

This setup follows the exact same pattern as Terra's successful deployment:

| Feature | Terra | Uptrack |
|---------|-------|---------|
| Deployment Tool | Colmena | ✅ Colmena |
| Installation | nixos-anywhere | ✅ nixos-anywhere |
| Disk Partitioning | Disko | ✅ Disko |
| Secrets | Agenix | ✅ Agenix |
| Helper Script | nixos-deploy.sh | ✅ nixos-deploy.sh |
| Provider | Hetzner | Hetzner + Contabo |
| App | Phoenix | Phoenix |
| Database | PostgreSQL | PostgreSQL + TimescaleDB |
| Extra Services | None | ClickHouse |

## Resources

- [Colmena Manual](https://colmena.cli.rs/)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [Disko](https://github.com/nix-community/disko)
- [Agenix](https://github.com/ryantm/agenix)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
