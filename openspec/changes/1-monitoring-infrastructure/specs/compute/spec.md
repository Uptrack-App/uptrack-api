# Capability: infrastructure/compute

Infrastructure compute resources for multi-region deployment.

## ADDED Requirements

### Requirement: Node Provisioning and Naming
The system SHALL maintain an inventory of 5 compute nodes with provider-agnostic naming (eu-a, eu-b, eu-c, india-s, india-w).

**ID:** infra-compute-001
**Priority:** Critical

Generic names enable provider migration without config changes. Nodes follow pattern {region}-{role} where region is geographic (eu, india) and role is letter-based.

#### Scenario: List all active nodes
**Given** the infrastructure is deployed
**When** an operator queries the node inventory
**Then** the system returns all 5 nodes with their roles, specs, and health status

#### Scenario: Rename node after provider migration
**Given** eu-a is currently hosted on Hostkey (Italy)
**When** migrating to Netcup (Austria)
**Then** the hostname remains "eu-a" and Tailscale IP remains 100.64.1.1
**And** only metadata (provider, location) changes

---

### Requirement: Resource Allocation and Geographic Distribution
Each EU node SHALL have minimum 4 vCPU, 8GB RAM, 120GB NVMe storage, and the system SHALL deploy nodes in 2 geographic regions: EU (3 nodes) and Asia (2 nodes).

**ID:** infra-compute-002
**Priority:** High

Co-location reduces cost while maintaining performance. EU cluster provides low-latency HA, Asia nodes serve regional users and backups.

#### Scenario: EU node resource validation
**Given** a new EU node is provisioned
**When** the system validates its specifications
**Then** it confirms >= 4 vCPU, >= 8GB RAM, >= 120GB storage with NVMe or better
**And** CPU usage is <70%, memory <80%, disk <80% under normal load

#### Scenario: Measure inter-region latency
**Given** all nodes are operational
**When** measuring network round-trip time
**Then** EU nodes have <20ms RTT between each other
**And** India nodes have ~150ms RTT to EU nodes

---

### Requirement: Scalability and Node Replacement
The system SHALL support replacing any node without data loss or >2 minutes downtime, and SHALL document scaling triggers for 3x, 5x, and 10x current load.

**ID:** infra-compute-003
**Priority:** Medium

Provider migrations, hardware upgrades, and growth require node replacement and scaling procedures.

#### Scenario: Replace EU node with zero data loss
**Given** eu-b is operational with vmstorage2 and PostgreSQL replica
**When** a new node is added as replacement and data is synchronized
**Then** no metrics or database data is lost
**And** queries continue during the replacement

#### Scenario: Scale to 30,000 monitors (3x growth)
**Given** current load is 10,000 monitors
**When** user count grows to 300 users (30,000 monitors)
**Then** documentation specifies adding 1 vmstorage node
**And** expected storage usage increases to ~95GB total

#### Scenario: Scale to 100,000 monitors (10x growth)
**Given** current load is 10,000 monitors
**When** user count grows to 1,000 users
**Then** documentation specifies adding 5-7 vmstorage nodes and separating PostgreSQL to dedicated nodes
