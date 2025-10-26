# NixOS Infrastructure Configuration

This directory contains all NixOS configurations for Uptrack's multi-region deployment.

## Directory Structure

```
infra/nixos/
├── common/              # Shared base configurations
│   ├── base.nix        # Foundation for all nodes (SSH, firewall, packages, etc.)
│   ├── oracle.nix      # Oracle Cloud-specific (idle prevention, non-EFI boot)
│   ├── hetzner.nix     # Hetzner-specific (EFI boot, disko)
│   └── contabo.nix     # Contabo-specific (EFI boot, disko)
│
├── modules/             # Reusable modules
│   ├── services/       # Service definitions
│   │   ├── postgres.nix
│   │   ├── clickhouse.nix
│   │   ├── uptrack-app.nix
│   │   ├── haproxy.nix
│   │   └── etcd.nix
│   ├── packages/       # Custom packages
│   │   └── uptrack-app.nix
│   └── profiles/       # Service bundles
│       ├── primary.nix  # Full stack (app + postgres + clickhouse + haproxy)
│       ├── worker.nix   # App + postgres + clickhouse
│       └── minimal.nix  # Postgres only (Oracle free tier)
│
├── regions/            # Region-specific configurations
│   ├── europe/
│   │   ├── hetzner-primary/     # 91.98.89.119 (node-a)
│   │   │   └── default.nix
│   │   ├── contabo-secondary/   # 185.237.12.64 (node-b)
│   │   │   └── default.nix
│   │   └── contabo-tertiary/    # 147.93.146.35 (node-c)
│   │       └── default.nix
│   │
│   └── asia/
│       └── india-hyderabad/
│           ├── worker-1/        # 152.67.179.42 (node-india-strong)
│           │   └── default.nix
│           └── worker-2/        # TBD (node-india-weak)
│               └── default.nix
│
├── disko/              # Disk partitioning schemes
│   ├── hetzner-arm64.nix
│   ├── contabo-vps.nix
│   └── oracle-free-tier.nix (placeholder - Oracle uses pre-existing partitions)
│
└── secrets/            # Agenix secrets
    └── secrets.nix
```

## Node Naming Convention

### Production Nodes (Final 5-Node Architecture)
- `germany` → Europe Germany (Netcup ARM G11) - PG Primary + CH Replica
- `austria` → Europe Austria (Netcup ARM G11) - CH Primary + PG Replica
- `canada` → Americas Canada (OVH VPS-1) - App-only + etcd
- `india-hyderabad-1` → Asia India (Oracle Free) - PG Replica (152.67.179.42)
- `india-hyderabad-2` → Asia India (Oracle Free) - App-only + etcd (129.159.22.183)

### Legacy Names (Deprecated - To Be Removed After Migration)
- ~~`hetzner-primary`~~ → (91.98.89.119) - Old node-a, will be decommissioned
- ~~`contabo-secondary`~~ → (185.237.12.64) - Old node-b, will be decommissioned
- ~~`contabo-tertiary`~~ → (147.93.146.35) - Old node-c, will be decommissioned

## Deployment Commands

### Deploy to all nodes
```bash
colmena apply
```

### Deploy to specific node (Production)
```bash
colmena apply --on germany
colmena apply --on austria
colmena apply --on canada
colmena apply --on india-hyderabad-1
colmena apply --on india-hyderabad-2
```

### Deploy by tags
```bash
# Production nodes
colmena apply --on @netcup              # Netcup nodes (Germany, Austria)
colmena apply --on @ovh                 # OVH nodes (Canada)
colmena apply --on @oracle              # Oracle Cloud nodes (India)
colmena apply --on @europe              # Europe region only
colmena apply --on @americas            # Americas region only
colmena apply --on @asia                # Asia region only

# Database roles
colmena apply --on @postgres-primary    # PostgreSQL primary (Germany)
colmena apply --on @clickhouse-primary  # ClickHouse primary (Austria)
colmena apply --on @app-only            # App-only nodes (Canada, India-2)

# Legacy nodes (deprecated)
colmena apply --on @legacy              # All legacy nodes
```

### Install fresh NixOS (nixos-anywhere)
```bash
# Production nodes
nix run .#install-germany
nix run .#install-austria
nix run .#install-canada
nix run .#install-india-hyderabad-1
nix run .#install-india-hyderabad-2
```

## Adding a New Region

Example: Adding Singapore Oracle worker

1. **Create region directory structure**
```bash
mkdir -p infra/nixos/regions/asia/singapore/worker-1
```

2. **Create node configuration**
```bash
# infra/nixos/regions/asia/singapore/worker-1/default.nix
{ config, pkgs, lib, ... }:

let
  vars = {
    username = "le";
    sshKey = "ssh-ed25519 AAAA...";
  };
in {
  imports = [
    ../../../../common/base.nix
    ../../../../common/oracle.nix
    ../../../../modules/profiles/minimal.nix
  ];

  networking.hostName = "uptrack-singapore-1";

  environment.variables = {
    NODE_NAME = "singapore-1";
    NODE_REGION = "asia";
    NODE_PROVIDER = "oracle";
    NODE_LOCATION = "singapore";
  };

  # ... rest of node-specific config
}
```

3. **Add to flake.nix**
```nix
# In colmena section
singapore-1 = {
  deployment = {
    targetHost = "SINGAPORE_IP";
    targetUser = "le";
    tags = [ "worker" "oracle" "asia" "singapore" "postgres" "minimal" "arm64" ];
    buildOnTarget = true;
    allowLocalDeployment = false;
  };

  nixpkgs.system = "aarch64-linux";

  imports = [
    agenixModule
    ./infra/nixos/regions/asia/singapore/worker-1
  ];
};

# In nixosConfigurations section
singapore-1 = nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    agenixModule
    ./infra/nixos/regions/asia/singapore/worker-1
  ];
  specialArgs = { inherit self; };
};
```

4. **Deploy**
```bash
colmena apply --on singapore-1
```

## Service Profiles

### Primary Profile
- Full stack deployment
- Services: Uptrack app, PostgreSQL, ClickHouse, HAProxy
- Used by: `hetzner-primary`

### Worker Profile
- Worker node deployment
- Services: Uptrack app, PostgreSQL, ClickHouse
- Used by: `contabo-secondary`, `contabo-tertiary`

### Minimal Profile
- Minimal deployment for resource-constrained environments
- Services: PostgreSQL only (app deployed as release)
- Used by: Oracle Cloud Free Tier nodes (`india-hyderabad-1`, `india-hyderabad-2`)

## Provider-Specific Notes

### Oracle Cloud
- Uses non-EFI boot (MBR GRUB on /dev/sda)
- Pre-existing partitions (no disko)
- Includes idle prevention (avoid instance reclamation)
- Recommends PostgreSQL 17 JIT for ARM64 performance
- Boot menu timeout: 10 seconds (for rollback)

### Hetzner
- Uses EFI boot
- Declarative partitioning with disko
- ARM64 architecture

### Contabo
- Uses EFI boot
- Declarative partitioning with disko
- x86_64 architecture

## Migration from Old Structure

The old flat structure has been migrated to a hierarchical region-based structure:

### Before
```
infra/nixos/
├── common.nix
├── common-oracle.nix
├── disko.nix
├── node-a.nix
├── node-b.nix
├── node-c.nix
├── node-india-strong.nix
├── node-india-weak.nix
├── services/
└── packages/
```

### After
```
infra/nixos/
├── common/
│   ├── base.nix (merged from common.nix)
│   ├── oracle.nix (from common-oracle.nix)
│   ├── hetzner.nix (new)
│   └── contabo.nix (new)
├── modules/
│   ├── services/ (from old services/)
│   ├── packages/ (from old packages/)
│   └── profiles/ (new)
├── regions/
│   ├── europe/
│   │   ├── hetzner-primary/ (from node-a.nix)
│   │   ├── contabo-secondary/ (from node-b.nix)
│   │   └── contabo-tertiary/ (from node-c.nix)
│   └── asia/
│       └── india-hyderabad/
│           ├── worker-1/ (from node-india-strong-minimal.nix)
│           └── worker-2/ (from node-india-weak.nix)
└── disko/
    ├── hetzner-arm64.nix (from disko.nix)
    ├── contabo-vps.nix (from disko.nix)
    └── oracle-free-tier.nix (placeholder)
```

## Benefits of New Structure

1. **Scalable** - Easy to add new regions/workers
2. **Clear hierarchy** - Region → Provider → Instance
3. **Consistent naming** - `asia/india-hyderabad/worker-1` vs `node-india-strong`
4. **Reusable profiles** - Apply "minimal" profile to all Oracle free tier nodes
5. **Better git organization** - Regional teams can work on their regions independently
6. **DRY principle** - Shared configs in `common/`, region-specific configs in `regions/`
