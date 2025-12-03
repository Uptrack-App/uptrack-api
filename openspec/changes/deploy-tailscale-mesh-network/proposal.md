# Proposal: Deploy Tailscale Mesh Network

**Status:** Draft
**Created:** 2025-10-30
**Owner:** Infrastructure Team

## Summary

Deploy Tailscale VPN mesh network across all 5 infrastructure nodes (3 EU Hostkey Italy + 2 India Oracle Cloud) to establish secure, encrypted communication channels before deploying application services.

## Why

**Problem:**
- 5 nodes across 2 providers (Hostkey Italy, Oracle Cloud India) need to communicate securely
- Public IP-based communication requires complex firewall rules (140+ rules) and is unencrypted
- Provider migrations (future: Hostkey → Netcup) would require IP reconfiguration across all services

**Business Impact:**
- **Without Tailscale:** Each service (PostgreSQL, etcd, VictoriaMetrics) exposed to public internet = security risk
- **Without static IPs:** Provider migration = breaking change requiring config updates across all nodes
- **Current blocker:** Cannot deploy etcd cluster (requires secure low-latency network between EU nodes)

**Cost of delay:**
- Cannot proceed with PostgreSQL HA setup (depends on etcd, depends on Tailscale)
- Cannot deploy VictoriaMetrics cluster (requires secure inter-node communication)
- Infrastructure deployment blocked until secure networking established

## What

Deploy Tailscale mesh VPN to create a secure overlay network with the following characteristics:

### In Scope
- Install Tailscale on all 5 nodes:
  - **EU nodes (Hostkey Italy):** eu-a (REMOVED_IP), eu-b (REMOVED_IP), eu-c (REMOVED_IP)
  - **India nodes (Oracle Cloud):** india-s (152.67.179.42), india-w (REMOVED_IP)
- Assign static Tailscale IPs:
  - eu-a: 100.64.1.1
  - eu-b: 100.64.1.2
  - eu-c: 100.64.1.3
  - india-s: 100.64.1.10
  - india-w: 100.64.1.11
- Verify mesh connectivity between all nodes
- Configure automatic startup on boot
- Tag all nodes with `tag:infrastructure`

### Out of Scope
- Service configuration (PostgreSQL, etcd, VictoriaMetrics) - handled by separate spec
- Firewall hardening - will be part of subsequent security hardening
- ACL policies - basic default policies sufficient for now
- MagicDNS configuration - static IPs sufficient

### Success Criteria
- ✅ All 5 nodes visible in Tailscale admin console
- ✅ All nodes reachable via static Tailscale IPs
- ✅ Ping latency: EU internal <20ms, EU-India ~150ms
- ✅ SSH works via Tailscale IPs from any node
- ✅ Tailscale service auto-starts on boot
- ✅ Node inventory documentation updated with Tailscale IPs

## Affected Capabilities

### New Capabilities
- `infrastructure/tailscale-deployment` - NEW: Tailscale mesh network deployment

### Dependencies
- **Prerequisites:**
  - Tailscale account created (✅ hoangbytes@gmail.com)
  - Auth key generated (✅ expires Jan 28, 2026)
  - SSH access to all 5 nodes (✅ verified)
  - NixOS module created (✅ `infra/nixos/modules/services/tailscale.nix`)
  - Debian installation script created (✅ `scripts/install-tailscale-debian.sh`)

- **Blocks:**
  - `1-monitoring-infrastructure` (Phase 2: etcd cluster requires Tailscale)

## How

### Implementation Strategy

**Deployment method:**
1. **india-s (NixOS):** Deploy via `nixos-rebuild switch` with Tailscale module
2. **Other 4 nodes (Debian/Ubuntu):** Deploy via shell script that installs Tailscale package and connects

**Rollout order:**
1. Deploy to india-s first (NixOS, most complex)
2. Deploy to india-w (same region, test connectivity)
3. Deploy to eu-a, eu-b, eu-c (can be parallel)
4. Assign static IPs via Tailscale admin console
5. Verify connectivity matrix (all nodes can ping all others)

**Testing approach:**
- After each node: verify it appears in Tailscale admin console
- After all nodes: ping matrix test (5×5 = 25 tests)
- Latency verification (EU <20ms, cross-region ~150ms)
- SSH connectivity test via Tailscale IPs

### Risk Assessment

**Low Risk:**
- Tailscale is overlay network (doesn't affect existing connectivity)
- Can remove Tailscale if issues occur (no breaking changes)
- Deployment scripts tested and validated

**Mitigation:**
- Deploy one node at a time (can rollback per-node)
- Keep public SSH access (port 22) open during deployment
- Document rollback procedure (remove Tailscale, revert NixOS generation)

### Alternatives Considered

**Alternative 1: WireGuard manual setup**
- ❌ Rejected: Requires manual key management, complex multi-peer config
- ❌ No dynamic IP updates when nodes restart
- ❌ More operational overhead

**Alternative 2: Cloud provider VPN (AWS PrivateLink, etc.)**
- ❌ Rejected: Only works within single provider (we have Hostkey + Oracle)
- ❌ Vendor lock-in

**Alternative 3: OpenVPN**
- ❌ Rejected: Requires central server, slower performance
- ❌ More complex configuration

**Why Tailscale:**
- ✅ Built on WireGuard (modern, fast, secure)
- ✅ Automatic NAT traversal (works across any provider)
- ✅ Free tier supports 100 devices
- ✅ Easy management via web console
- ✅ Static IP assignment built-in

## Timeline

**Estimated duration:** 1-2 hours

- **Preparation (15 min):** Verify SSH access, auth key ready
- **Deployment (45 min):** Deploy to all 5 nodes sequentially
- **IP Assignment (10 min):** Assign static IPs via admin console
- **Verification (20 min):** Test connectivity, document results

## Open Questions

None - all prerequisites met, ready to deploy.
