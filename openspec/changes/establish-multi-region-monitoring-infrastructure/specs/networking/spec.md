# Capability: infrastructure/networking

Secure networking infrastructure using Tailscale mesh VPN.

## ADDED Requirements

### Requirement: Tailscale Mesh Network with Static IPs
The system SHALL establish a Tailscale mesh network connecting all 5 nodes with persistent private IPs that never change, even during provider migrations.

**ID:** infra-network-001
**Priority:** Critical

Tailscale provides zero-trust security, encryption, and works across multiple hosting providers. Static IPs (100.64.1.1-3, 100.64.1.10-11) enable hardcoded configs that survive node replacement.

#### Scenario: All nodes join Tailscale network
**Given** Tailscale is installed on all 5 nodes
**When** each node joins the tailnet with tag "uptrack-prod"
**Then** all nodes can ping each other via Tailscale IPs
**And** each node has a stable IP: eu-a=100.64.1.1, eu-b=100.64.1.2, eu-c=100.64.1.3, india-s=100.64.1.10, india-w=100.64.1.11

#### Scenario: IP persistence across migrations
**Given** eu-a initially has Tailscale IP 100.64.1.1 on Hostkey
**When** migrating eu-a to Netcup Austria
**Then** the new Netcup node receives the same Tailscale IP 100.64.1.1
**And** all services continue using 100.64.1.1 without config changes

---

### Requirement: Network Security and Encryption
All service-to-service communication SHALL use Tailscale encrypted tunnels (WireGuard), and public firewall SHALL only allow ports 22 (SSH) and 443 (HTTPS).

**ID:** infra-network-002
**Priority:** Critical

Minimizes attack surface by keeping internal services (PostgreSQL, etcd, VictoriaMetrics) private and encrypted.

#### Scenario: PostgreSQL replication over Tailscale
**Given** PostgreSQL primary is on eu-a (100.64.1.1)
**When** replica on eu-b connects for replication
**Then** the connection uses Tailscale IP 100.64.1.1:5432
**And** traffic is encrypted via WireGuard
**And** no PostgreSQL port is exposed to public internet

#### Scenario: Verify public port exposure
**Given** the firewall is configured
**When** scanning a node's public IP from internet
**Then** only ports 22 and 443 respond
**And** ports 5432, 2379, 8400, etc. are filtered/closed

---

### Requirement: Network Operations and Performance
Nodes SHALL resolve each other by hostname via Tailscale MagicDNS, and Tailscale WireGuard encryption SHALL add <3ms latency overhead and use <0.1 vCPU per node.

**ID:** infra-network-003
**Priority:** Medium

Human-readable names improve operations, and minimal overhead ensures security doesn't degrade performance.

#### Scenario: Resolve hostname to Tailscale IP
**Given** MagicDNS is enabled
**When** running `ping eu-b` from eu-a
**Then** it resolves to 100.64.1.2
**And** the ping succeeds via Tailscale tunnel

#### Scenario: Measure Tailscale latency overhead
**Given** two EU nodes with 20ms base latency
**When** using Tailscale tunnel
**Then** observed latency is <=23ms (20ms base + 3ms overhead)
**And** WireGuard uses <0.1 vCPU (<2.5% of 4 vCPU)
