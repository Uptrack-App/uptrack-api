# Capability: deployment/nixos-profiles

NixOS configuration profiles for composable infrastructure and worker deployments.

## ADDED Requirements

### Requirement: Profile-Based NixOS Configuration Structure
The system SHALL provide three composable NixOS profiles (base.nix, infrastructure.nix, worker.nix), node configurations SHALL import profiles using NixOS modules system, and adding a new worker node SHALL require <15 lines of configuration.

**ID:** nixos-profiles-001
**Priority:** Critical

Profile architecture enables rapid regional expansion. Adding Tokyo worker should take minutes, not hours.

#### Scenario: Infrastructure node imports both profiles
**Given** eu-a needs PostgreSQL + VictoriaMetrics + workers
**When** eu-a/default.nix is defined
**Then** imports list contains: [base.nix, infrastructure.nix, worker.nix]
**And** nixos-rebuild builds successfully
**And** all services (PostgreSQL, VM, Uptrack worker) start on boot

#### Scenario: Worker-only node imports worker profile
**Given** future Tokyo node needs only workers (no databases)
**When** tokyo/default.nix is created with imports: [base.nix, worker.nix]
**Then** nixos-rebuild builds Tokyo configuration
**And** Tokyo node runs Uptrack worker but NOT PostgreSQL or VictoriaMetrics
**And** Tokyo worker connects to remote PostgreSQL (Germany)

#### Scenario: Adding new region takes <15 lines
**Given** operator wants to add Singapore worker
**When** creating regions/asia/singapore/default.nix
**Then** file contains:
  - imports (1 line)
  - hostname (1 line)
  - NODE_REGION variable (1 line)
  - Oban queue config (3 lines)
  - User SSH key (3 lines)
  - Firewall rules (2 lines)
  - Total: <15 lines ✅

---

### Requirement: Infrastructure Profile Definition
The infrastructure.nix profile SHALL configure PostgreSQL 17, VictoriaMetrics cluster components, etcd, and SHALL allocate resources for databases (PostgreSQL: 2GB RAM, VictoriaMetrics: 1.5GB RAM, etcd: 200MB RAM).

**ID:** nixos-profiles-002
**Priority:** Critical

Infrastructure profile encapsulates full stack configuration. Prevents drift between nodes.

#### Scenario: Infrastructure profile enables all databases
**Given** eu-a imports infrastructure.nix profile
**When** nixos-rebuild builds configuration
**Then** systemd services include:
  - postgresql.service (enabled, wants multi-user.target)
  - vmstorage.service (enabled)
  - vminsert.service (enabled)
  - etcd.service (enabled)

#### Scenario: Infrastructure profile sets resource limits
**Given** infrastructure.nix defines systemd service configs
**When** PostgreSQL service starts
**Then** PostgreSQL has MemoryMax=2.5G (allows 2GB + overhead)
**And** VictoriaMetrics has MemoryMax=2G
**And** etcd has MemoryMax=300M

#### Scenario: Profile is reusable across regions
**Given** infrastructure.nix is defined once
**When** eu-a, eu-b, eu-c all import infrastructure.nix
**Then** all three nodes run identical database configurations
**And** only node-specific values (hostnames, IPs) differ

---

### Requirement: Worker Profile Definition
The worker.nix profile SHALL configure Uptrack worker systemd service, SHALL set WORKER_REGION environment variable from node config, and SHALL configure Oban to subscribe to region-specific queue.

**ID:** nixos-profiles-003
**Priority:** Critical

Worker profile isolates application concerns. Enables worker-only nodes for cheap regional expansion.

#### Scenario: Worker profile creates systemd service
**Given** india-s imports worker.nix profile
**When** nixos-rebuild builds configuration
**Then** systemd services include uptrack-worker.service
**And** service ExecStart points to /nix/store/.../bin/uptrack_worker
**And** service Type=notify (systemd waits for worker readiness)

#### Scenario: Worker inherits region from node config
**Given** india-s defines environment.variables.NODE_REGION = "asia"
**When** worker.nix configures uptrack-worker.service
**Then** service Environment includes WORKER_REGION=asia
**And** worker application reads $WORKER_REGION at startup
**And** worker subscribes to checks_asia queue

#### Scenario: Worker profile sets resource limits
**Given** worker.nix defines systemd service config
**When** uptrack-worker service starts
**Then** service has MemoryMax=400M
**And** service has CPUQuota=50%
**And** service Restart=on-failure with RestartSec=5s

---

### Requirement: Profile Composition and Override
Node configurations SHALL be able to override profile defaults, profile imports SHALL use NixOS priority system (node > profile > default), and profiles SHALL validate required node-specific variables (NODE_REGION, hostname).

**ID:** nixos-profiles-004
**Priority:** Medium

Flexibility allows per-node customization while maintaining DRY principles.

#### Scenario: Node overrides worker concurrency
**Given** worker.nix sets default Oban concurrency to 10
**When** eu-a overrides with checks_eu concurrency = 20
**Then** eu-a worker processes 20 concurrent jobs
**And** india-s (no override) processes 10 concurrent jobs

#### Scenario: Profile validates required variables
**Given** worker.nix requires NODE_REGION to be set
**When** operator creates node config without NODE_REGION
**Then** nixos-rebuild fails with error: "NODE_REGION must be defined"
**And** error message suggests valid values: eu, asia, americas

#### Scenario: Node-specific firewall rules merge with profile
**Given** worker.nix opens ports 22, 4000, 9568
**When** tokyo node adds port 8080 (custom monitoring)
**Then** tokyo firewall allows: 22, 4000, 8080, 9568
**And** profile ports (22, 4000, 9568) are preserved
