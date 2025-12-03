# Capability: infrastructure/tailscale-deployment

Tailscale mesh VPN deployment across 5 infrastructure nodes for secure inter-node communication.

## ADDED Requirements

### Requirement: Tailscale Installation on All Nodes
The system SHALL install Tailscale on all 5 nodes and connect them to the Uptrack tailnet using the auth key with tag:infrastructure.

**ID:** tailscale-deploy-001
**Priority:** Critical

Establishes secure encrypted mesh network before any application services are deployed. Without this, services would communicate over public internet (insecure) or require 140+ manual firewall rules (error-prone).

#### Scenario: Install Tailscale on NixOS node (india-s)
**Given** india-s (152.67.179.42) is running NixOS
**When** deploying configuration with Tailscale module enabled
**Then** Tailscale service starts automatically
**And** node connects to tailnet with hostname "india-s"
**And** node appears in Tailscale admin console
**And** node has tag:infrastructure

#### Scenario: Install Tailscale on Debian/Ubuntu nodes (EU + india-w)
**Given** a Debian/Ubuntu node (eu-a, eu-b, eu-c, or india-w)
**When** running installation script with appropriate hostname
**Then** Tailscale package is installed from official repository
**And** node connects to tailnet with correct hostname
**And** node appears in Tailscale admin console within 30 seconds
**And** node has tag:infrastructure

#### Scenario: Tailscale persists across reboots
**Given** Tailscale is installed and connected
**When** node reboots
**Then** Tailscale service starts automatically on boot
**And** node reconnects to tailnet within 60 seconds
**And** Tailscale IP remains unchanged

---

### Requirement: Static IP Assignment
Each node SHALL be assigned a permanent Tailscale IP that never changes, even during provider migrations or node replacements.

**ID:** tailscale-deploy-002
**Priority:** Critical

Static IPs enable hardcoded service configurations that survive infrastructure changes. Without static IPs, every provider migration would require updating configs across all services (PostgreSQL, etcd, VictoriaMetrics).

#### Scenario: Assign static IPs to all nodes
**Given** all 5 nodes are connected to Tailscale
**When** operator assigns static IPs via Tailscale admin console
**Then** the following IPs are permanently assigned:
  - eu-a: 100.64.1.1
  - eu-b: 100.64.1.2
  - eu-c: 100.64.1.3
  - india-s: 100.64.1.10
  - india-w: 100.64.1.11
**And** IPs persist even if node disconnects and reconnects

#### Scenario: Verify static IP assignment
**Given** static IPs have been assigned
**When** running `tailscale ip -4` on each node
**Then** each node reports its assigned static IP
**And** the IP matches the documented inventory

---

### Requirement: Mesh Connectivity Verification
All nodes SHALL be able to communicate with all other nodes via Tailscale IPs with expected latency characteristics.

**ID:** tailscale-deploy-003
**Priority:** High

Verifies that the mesh network functions correctly before deploying application services that depend on it.

#### Scenario: Ping connectivity within EU
**Given** all EU nodes (eu-a, eu-b, eu-c) are connected
**When** pinging between EU nodes via Tailscale IPs
**Then** all nodes respond successfully
**And** average latency is <20ms
**And** packet loss is 0%

#### Scenario: Ping connectivity EU to India
**Given** EU and India nodes are all connected
**When** pinging from any EU node to any India node
**Then** India nodes respond successfully
**And** average latency is 140-160ms
**And** packet loss is <1%

#### Scenario: SSH access via Tailscale IPs
**Given** all nodes have Tailscale IPs assigned
**When** attempting SSH to each node via its Tailscale IP
**Then** SSH connection succeeds from any other node
**And** authentication works with configured keys
**And** connection is established within 5 seconds

#### Scenario: Connectivity matrix test
**Given** all 5 nodes are connected
**When** running ping test from each node to all other nodes (5×4=20 tests)
**Then** all 20 ping tests succeed
**And** results are documented in node-inventory.md

---

### Requirement: Auto-start on Boot
Tailscale service SHALL start automatically on system boot and SHALL reconnect to the tailnet without manual intervention.

**ID:** tailscale-deploy-004
**Priority:** High

Ensures network remains available after node restarts or updates. Manual reconnection would cause downtime for critical services.

#### Scenario: Auto-reconnect after reboot (NixOS)
**Given** india-s has Tailscale configured via NixOS module
**When** system reboots
**Then** tailscaled.service starts during boot
**And** tailscale-autoconnect.service runs after tailscaled
**And** node reconnects to tailnet using existing credentials
**And** no auth key is required (uses saved credentials)
**And** Tailscale IP remains 100.64.1.10

#### Scenario: Auto-reconnect after reboot (Debian)
**Given** eu-a has Tailscale installed via package
**When** system reboots
**Then** tailscaled systemd service starts automatically
**And** node reconnects using saved state
**And** Tailscale IP remains 100.64.1.1

---

### Requirement: Documentation and Inventory
Node inventory documentation SHALL be updated with Tailscale IPs and connectivity status.

**ID:** tailscale-deploy-005
**Priority:** Medium

Maintains single source of truth for node IPs (both public and Tailscale) to aid troubleshooting and future development.

#### Scenario: Update node inventory
**Given** all nodes are deployed with Tailscale
**When** updating docs/infrastructure/node-inventory.md
**Then** each node entry includes:
  - Public IP
  - Tailscale IP
  - SSH command using Tailscale IP
  - Last verified date
**And** document includes connectivity matrix results

#### Scenario: Verify documentation accuracy
**Given** node-inventory.md is updated
**When** operator follows SSH commands from documentation
**Then** all SSH commands work successfully
**And** IPs in documentation match actual node IPs
