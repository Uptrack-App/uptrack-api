# Capability: deployment/cheap-workers

Ultra-low-cost VPS nodes for regional monitoring workers using providers under $2/month.

## ADDED Requirements

### Requirement: Ultra-Cheap VPS Provider Selection
The system SHALL support deploying workers on VPS providers costing <$2/month, worker nodes SHALL have minimum 512MB RAM and 1 vCPU, and the system SHALL maintain a list of vetted providers (RackNerd, Dedirock, nube.sh, Vultr spot instances).

**ID:** cheap-workers-001
**Priority:** High

Ultra-cheap VPS enables global coverage at minimal cost. $1.50/month × 10 regions = $15/month vs $250+/month with premium providers.

#### Scenario: Deploy worker on RackNerd $10/year VPS
**Given** RackNerd offers 768MB RAM, 1 vCPU, 10GB SSD for $10.18/year ($0.85/month)
**When** deploying Uptrack worker using NixOS minimal profile
**Then** worker uses <300MB RAM (leaving 468MB free)
**And** worker processes checks from assigned region
**And** monthly cost is $0.85 (vs $2.50 Vultr, $4 Hetzner)

#### Scenario: Validate provider meets minimum requirements
**Given** provider offers VPS with 512MB RAM, 1 vCPU, 5GB storage
**When** checking against worker requirements
**Then** provider is approved for worker deployment
**And** provider is added to vetted list if:
  - IPv4 address included
  - Supports custom OS (NixOS)
  - Network uptime >99%
  - No CPU throttling during checks

#### Scenario: Reject insufficient VPS
**Given** provider offers 256MB RAM VPS at $0.50/month
**When** checking against worker requirements
**Then** provider is rejected (insufficient RAM)
**And** minimum 512MB RAM is required (worker uses ~280MB + 100MB system)

---

### Requirement: Multi-Provider Worker Deployment Strategy
The system SHALL deploy workers across multiple cheap providers to reduce vendor lock-in, each region SHALL have workers from 2+ different providers for redundancy, and provider failures SHALL not affect checks (Oban queues persist jobs).

**ID:** cheap-workers-002
**Priority:** Medium

Multi-provider strategy prevents single provider outage from affecting entire region. If RackNerd Tokyo is down, nube.sh Tokyo continues processing checks.

#### Scenario: Deploy Tokyo region with 2 providers
**Given** Tokyo region needs coverage
**When** deploying workers
**Then** tokyo-worker-1 runs on RackNerd Tokyo ($0.85/month)
**And** tokyo-worker-2 runs on nube.sh Tokyo ($1.50/month)
**And** both workers subscribe to checks_asia queue
**And** Oban distributes load across both workers (SKIP LOCKED)

#### Scenario: RackNerd Tokyo outage
**Given** tokyo-worker-1 (RackNerd) is down due to provider issue
**When** scheduler inserts jobs to checks_asia queue
**Then** tokyo-worker-2 (nube.sh) processes all Asia checks
**And** jobs queue normally (no data loss)
**And** alert fires: "WorkerDown: tokyo-worker-1"

#### Scenario: Provider diversity across regions
**Given** deploying workers to 10 regions
**When** selecting providers
**Then** each region uses different provider mix:
  - Tokyo: RackNerd + nube.sh
  - Singapore: Dedirock + Vultr spot
  - São Paulo: Contabo + RackNerd
**And** no single provider failure affects >30% of regions

---

### Requirement: Cost Optimization and Provider Comparison
The system SHALL maintain cost comparison database for worker-suitable VPS, SHALL prioritize annual plans (lower monthly cost), and SHALL document total cost per region including all fees (setup, bandwidth overages).

**ID:** cheap-workers-003
**Priority:** Medium

Annual plans often 50-70% cheaper than monthly. RackNerd $10.18/year ($0.85/month) vs $2.50/month Vultr = 66% savings.

#### Scenario: Compare providers for Tokyo deployment
**Given** need worker in Tokyo region
**When** evaluating providers
**Then** comparison shows:

| Provider | Plan | RAM | Storage | Cost/mo | Cost/year | Network | Notes |
|----------|------|-----|---------|---------|-----------|---------|-------|
| RackNerd | Tokyo VPS | 768MB | 10GB | $0.85 | $10.18 | 1TB | Annual only ✅ |
| nube.sh | Tokyo Basic | 1GB | 15GB | $1.50 | $18 | 1TB | Monthly ✅ |
| Vultr | Tokyo Regular | 512MB | 10GB | $2.50 | $30 | 500GB | Hourly billing |
| Dedirock | Tokyo Micro | 512MB | 8GB | $1.20 | $14.40 | 500GB | Annual only |

**And** RackNerd selected for best value (768MB RAM, lowest cost)

#### Scenario: Calculate total regional cost
**Given** deploying Tokyo region with 2 workers (redundancy)
**When** calculating annual cost
**Then** total cost = RackNerd ($10.18) + nube.sh ($18) = $28.18/year
**And** monthly equivalent = $2.35/month for 2-worker redundant Tokyo region
**And** vs premium (2× Vultr) = $60/year savings per region

#### Scenario: Bandwidth overage cost
**Given** worker performs 10K checks/day × 5KB average = 50MB/day = 1.5GB/month
**When** checking against provider limits
**Then** RackNerd 1TB limit is sufficient (0.15% usage)
**And** no bandwidth overage fees expected

---

### Requirement: Automated Provider Health Monitoring
The system SHALL monitor provider uptime and performance, SHALL automatically mark providers as degraded if worker latency exceeds 200ms, and SHALL alert when cheap provider shows consistent issues (consider migration).

**ID:** cheap-workers-004
**Priority:** Low

Cheap providers may have lower reliability. Automated monitoring detects issues before users complain.

#### Scenario: Detect degraded cheap provider
**Given** tokyo-worker-1 (RackNerd) normally completes checks in 50ms
**When** check duration exceeds 200ms for 30 consecutive checks
**Then** alert fires: "ProviderDegraded: RackNerd Tokyo"
**And** alert includes: avg_latency=250ms, p95=300ms, p99=500ms
**And** ops team considers migrating to different Tokyo provider

#### Scenario: Track provider reliability
**Given** workers deployed on 10 cheap providers
**When** querying provider reliability dashboard
**Then** dashboard shows per-provider metrics:
  - Uptime % (last 30 days)
  - Average check latency
  - Failed checks % (network timeouts)
  - Cost per successful check
**And** providers sorted by reliability score

#### Scenario: Automatic failover to redundant worker
**Given** tokyo-worker-1 (RackNerd) is marked degraded
**When** Oban distributes jobs
**Then** tokyo-worker-2 (nube.sh) receives majority of jobs
**And** tokyo-worker-1 continues processing (not disabled, just deprioritized)
**And** when RackNerd performance improves, distribution rebalances

---

### Requirement: Cheap Worker Deployment Documentation
The system SHALL provide step-by-step guides for deploying on each vetted provider, SHALL include troubleshooting for provider-specific issues, and SHALL document provider signup process (account creation, payment methods, KYC requirements).

**ID:** cheap-workers-005
**Priority:** Medium

Each cheap provider has unique quirks. Documentation prevents wasted time on trial-and-error.

#### Scenario: RackNerd deployment guide
**Given** operator wants to deploy Tokyo worker on RackNerd
**When** following deployment guide at /docs/deployment/providers/racknerd.md
**Then** guide includes:
  1. Account signup (email verification, payment via PayPal/CC)
  2. Selecting correct plan (Tokyo VPS, annual billing)
  3. OS installation (Debian 12, then NixOS kexec)
  4. NixOS configuration (import worker.nix profile)
  5. Provider-specific notes (RackNerd uses Virtualizor panel)
  6. Expected provision time (5-30 minutes)

#### Scenario: Provider-specific issue documentation
**Given** RackNerd worker fails to connect to Tailscale
**When** operator checks troubleshooting guide
**Then** guide shows known issue: "RackNerd blocks UDP port 41641 (Tailscale DERP)"
**And** solution: "Use Tailscale relay mode or open support ticket"
**And** workaround: "Configure Tailscale to use only HTTPS relay"

#### Scenario: Provider comparison decision tree
**Given** operator unsure which cheap provider to use for São Paulo
**When** following provider selection guide
**Then** decision tree asks:
  - Need monthly billing? → Vultr/nube.sh
  - Need annual (cheapest)? → RackNerd/Dedirock
  - Need >1GB RAM? → nube.sh/Vultr
  - Need IPv6? → Check provider specs
**And** guide recommends best fit based on requirements

---

## Cost Analysis

### Global Coverage Cost Comparison

**10 regions with ultra-cheap workers (RackNerd + nube.sh redundancy):**

| Region | Primary Worker | Backup Worker | Annual Cost |
|--------|----------------|---------------|-------------|
| Tokyo | RackNerd $10.18 | nube.sh $18 | $28.18 |
| Singapore | RackNerd $10.18 | Dedirock $14.40 | $24.58 |
| Mumbai | RackNerd $10.18 | nube.sh $18 | $28.18 |
| São Paulo | RackNerd $12 | Contabo $18 | $30 |
| New York | RackNerd $10.18 | Vultr $30 | $40.18 |
| London | Dedirock $14.40 | Hetzner $48 | $62.40 |
| Frankfurt | RackNerd $10.18 | Hetzner $48 | $58.18 |
| Sydney | RackNerd $12 | Vultr $30 | $42 |
| Toronto | RackNerd $10.18 | Vultr $30 | $40.18 |
| Johannesburg | Contabo $18 | Vultr $30 | $48 |

**Total: $401.88/year = $33.49/month for 20 workers (10 regions × 2 redundancy)**

**vs Premium providers (Vultr/Hetzner only):**
- 20 workers × $30/year = $600/year = $50/month
- **Savings: $200/year (33% cheaper)**

**vs Super Premium (DigitalOcean/Linode):**
- 20 workers × $48/year = $960/year = $80/month
- **Savings: $558/year (58% cheaper)**

---

## Vetted Provider List

### Tier 1: Ultra-Cheap Annual ($10-15/year)

**RackNerd** ⭐ Recommended
- **Cost**: $10.18-12/year ($0.85-1/month)
- **Specs**: 768MB-1GB RAM, 1 vCPU, 10-15GB SSD
- **Locations**: LA, Seattle, Chicago, NYC, Dallas, Atlanta, Netherlands, France, Singapore, Tokyo
- **Pros**: Cheapest, annual billing, good reliability
- **Cons**: Annual only (no monthly), slow provisioning (5-24 hours)
- **Use case**: Primary worker for most regions

**Dedirock**
- **Cost**: $14.40/year ($1.20/month)
- **Specs**: 512MB-1GB RAM, 1 vCPU, 8-12GB SSD
- **Locations**: Multiple (check website)
- **Pros**: Competitive pricing, annual billing
- **Cons**: Less well-known, fewer reviews
- **Use case**: Backup worker or RackNerd alternative

### Tier 2: Budget Monthly ($1.50-2.50/month)

**nube.sh** ⭐ Recommended for monthly
- **Cost**: $1.50-2/month (~$18-24/year)
- **Specs**: 1GB RAM, 1 vCPU, 15GB SSD
- **Locations**: Silicon Valley, Tokyo, Hong Kong, Singapore, Johor Bahru
- **Pros**: Monthly billing, good Asia coverage, AMD EPYC CPUs
- **Cons**: Limited locations, higher than annual plans
- **Use case**: Backup worker, regions needing monthly billing

**Contabo**
- **Cost**: $1.50-2/month (~$18-24/year)
- **Specs**: 4GB RAM, 4 vCPU, 50GB SSD (oversold, actual performance lower)
- **Locations**: Germany, UK, US, Singapore, Australia, Japan
- **Pros**: High specs on paper, many locations
- **Cons**: Oversold (shared CPU performance varies), mixed reviews
- **Use case**: Backup worker, high-RAM needs

### Tier 3: Spot/Preemptible (Variable, risky)

**Vultr Spot Instances**
- **Cost**: $0.50-1.50/month (variable, can be terminated anytime)
- **Specs**: 512MB-2GB RAM, 1-2 vCPU
- **Locations**: 25+ globally
- **Pros**: Very cheap, global coverage
- **Cons**: Can be terminated with 2-minute notice, unstable pricing
- **Use case**: Experimental only, NOT recommended for production workers

---

## Risk Mitigation

### Provider Risks

| Risk | Mitigation |
|------|------------|
| Provider shutdown | Deploy 2+ providers per region |
| Account suspension | Keep backups of NixOS configs, can redeploy elsewhere in <30min |
| Price increase | Annual billing locks price for 1 year |
| Performance degradation | Monitor latency, auto-alert, migrate if persistent |
| Network outage | Oban queues jobs, processes when worker returns |
| Data loss | Workers are stateless, no data stored locally |

### Deployment Strategy

1. **Start with Tier 1 (RackNerd)** for cost-effectiveness
2. **Add Tier 2 (nube.sh) for redundancy** in critical regions
3. **Avoid Tier 3 (Spot)** for production workers
4. **Diversify providers** across regions (no single provider >40% of workers)
5. **Test provider** with 1 worker before deploying to multiple regions
6. **Monitor reliability** and replace poor performers

---

## Implementation Notes

### Provider-Specific Considerations

**RackNerd:**
- Provision time: 5-24 hours (manual approval sometimes)
- Payment: PayPal, Credit Card (no crypto)
- KYC: None required for small VPS
- Panel: Virtualizor (basic, functional)
- IPv6: Included
- NixOS: Install Debian first, then kexec to NixOS

**nube.sh:**
- Provision time: <1 hour (automated)
- Payment: Credit Card, potentially crypto
- Panel: Custom (modern)
- IPv6: Check availability
- NixOS: May support custom ISO upload

**Dedirock:**
- Provision time: Varies
- Check website for current offerings and provisioning details
- NixOS: Likely requires Debian/Ubuntu → kexec method

### Worker RAM Optimization

To fit in 512MB VPS:
- Disable Oban Pro features (use basic Oban)
- Set Ecto pool_size: 3 (instead of 10)
- Reduce Oban concurrency: 5 (instead of 10)
- Disable local caching
- Use minimal Elixir release (no dev dependencies)

Expected RAM usage:
- BEAM VM: 50MB
- Ecto (3 connections): 15MB
- Oban (5 workers): 15MB
- Finch HTTP: 15MB
- Working memory: 100MB
- System (NixOS minimal): 100MB
- **Total: ~295MB (leaving 217MB free on 512MB VPS)**
