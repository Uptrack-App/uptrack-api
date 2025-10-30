# Cheap VPS Provider Resources

**Purpose**: Track ultra-cheap VPS providers for regional monitoring workers

---

## Key Resources

### LowEndBox - VPS Deal Aggregator

**Main site**: https://lowendbox.com/

**Best cheap VPS guide**: https://lowendbox.com/best-cheap-vps-hosting-updated-2020/
- Updated regularly with vetted cheap providers
- Reviews and user feedback
- Price comparisons

**$1 VPS list**: https://lowendbox.com/blog/1-vps-1-usd-vps-per-month/
- Providers offering VPS under $1/month
- Great for worker-only nodes
- Check reviews before purchasing (some are oversold/unreliable)

---

## Recommended Providers (Vetted for Uptrack Workers)

### Tier 1: Ultra-Cheap Annual ($10-15/year = $0.85-1.25/month)

**RackNerd** ⭐
- **Site**: https://www.racknerd.com/
- **Cost**: $10.18-12/year
- **Specs**: 768MB-1GB RAM, 1 vCPU, 10-15GB SSD, 1TB bandwidth
- **Locations**: US (LA, Seattle, NYC, Chicago, Dallas, Atlanta), EU (Netherlands, France), Asia (Singapore, Tokyo)
- **Worker suitability**: ✅ Excellent (tested, reliable)
- **Purchase**: https://my.racknerd.com/cart.php
- **Notes**: Best value, annual billing only, provision time 5-24 hours

**Dedirock**
- **Site**: https://billing.dedirock.com/
- **Cost**: $14.40/year ($1.20/month)
- **Specs**: 512MB-1GB RAM, 1 vCPU, 8-12GB SSD
- **Purchase**: https://billing.dedirock.com/cart.php?a=confproduct&i=0
- **Worker suitability**: ✅ Good (needs testing)

### Tier 2: Budget Monthly ($1.50-2/month)

**nube.sh (Nube Cloud)**
- **Site**: https://nube.sh/
- **Cost**: $1.50-2/month (~$18-24/year)
- **Specs**: 1GB RAM, 1 vCPU, 15GB SSD, AMD EPYC Zen 3
- **Locations**: Silicon Valley, Tokyo, Hong Kong, Singapore, Johor Bahru
- **Worker suitability**: ✅ Excellent (good for Asia)
- **Notes**: Monthly billing, premium hardware, good reliability

**Contabo**
- **Site**: https://contabo.com/
- **Cost**: €1.50/month (~$1.70/month)
- **Specs**: 4GB RAM, 4 vCPU, 50GB SSD (oversold, actual lower)
- **Locations**: Germany, UK, US, Singapore, Australia, Japan
- **Worker suitability**: ⚠️ Fair (oversold, variable performance)
- **Notes**: High specs on paper but shared resources

---

## Evaluation Criteria

### Must-Have (Deal Breakers)

- ✅ **Minimum 512MB RAM** (worker needs ~280MB + 100MB system)
- ✅ **1 vCPU** (dedicated or shared acceptable)
- ✅ **5GB storage minimum** (NixOS minimal + worker)
- ✅ **IPv4 address** (required for Tailscale)
- ✅ **Custom OS support** (Debian/Ubuntu → kexec to NixOS)
- ✅ **>99% network uptime** (per reviews/monitoring)

### Nice-to-Have

- 🟢 **Monthly billing option** (easier to cancel if issues)
- 🟢 **IPv6 included** (future-proofing)
- 🟢 **>500GB bandwidth** (workers use ~1.5GB/month)
- 🟢 **Fast provisioning** (<1 hour)
- 🟢 **Good support** (in case of issues)

### Red Flags (Avoid)

- ❌ **CPU throttling** (some providers limit CPU to 10-20%)
- ❌ **Hidden fees** (setup fees, bandwidth overages)
- ❌ **Poor reviews** (<3.5 stars on Trustpilot/LowEndBox)
- ❌ **Frequent downtime** (>1% downtime = ~7 hours/month)
- ❌ **No custom OS** (can't install NixOS)

---

## Testing New Providers

### Before bulk deployment, test with 1 worker:

1. **Purchase 1 VPS** in target region
2. **Deploy NixOS + Uptrack worker** (follow deployment guide)
3. **Monitor for 1 week**:
   - CPU usage during checks
   - Network latency to PostgreSQL (Germany)
   - Check completion time
   - Any provider throttling/issues
4. **Evaluate reliability**:
   - Uptime % (target: >99.5%)
   - Check failure rate (target: <1%)
   - Average latency (target: <100ms local checks)
5. **Decision**:
   - ✅ Pass → Deploy to more regions
   - ❌ Fail → Request refund, try different provider

---

## Cost Examples

### Single Region (Tokyo) - 2 workers for redundancy

**Option A: Ultra-Cheap (RackNerd + nube.sh)**
- RackNerd Tokyo: $10.18/year
- nube.sh Tokyo: $18/year
- **Total: $28.18/year = $2.35/month**

**Option B: Budget (both nube.sh)**
- nube.sh Tokyo #1: $18/year
- nube.sh Tokyo #2: $18/year
- **Total: $36/year = $3/month**

**Option C: Premium (Vultr/Hetzner)**
- Vultr Tokyo: $30/year
- Hetzner Tokyo: $48/year
- **Total: $78/year = $6.50/month**

**Savings with Option A: $50/year per region (64% cheaper than premium)**

### Global Coverage (10 regions × 2 workers)

**Ultra-Cheap Strategy:**
- 10 primary workers (RackNerd): ~$110/year
- 10 backup workers (mix of nube.sh/Dedirock): ~$180/year
- **Total: $290/year = $24/month for 20 workers**

**Premium Strategy:**
- 20 workers (Vultr/Hetzner): ~$600-800/year = $50-66/month
- **Savings: $310-510/year (52-64% cheaper)**

---

## Provider-Specific Notes

### RackNerd

**Pros:**
- Excellent value ($0.85/month with annual)
- Good network (1Gbps, 1TB bandwidth)
- Many locations (US, EU, Asia)
- Reliable uptime

**Cons:**
- Annual billing only (no monthly)
- Slow provisioning (5-24 hours, sometimes manual)
- Virtualizor panel (basic but functional)

**Deployment notes:**
- Install Debian 12 first (from panel)
- Use kexec to switch to NixOS
- Tailscale works fine (no UDP blocks reported)

### nube.sh

**Pros:**
- Monthly billing available
- AMD EPYC Zen 3 (good performance)
- Asia-focused locations
- Fast provisioning (<1 hour)

**Cons:**
- More expensive than RackNerd annual
- Limited locations (5 total, all Asia/US West)

**Deployment notes:**
- Modern panel, easy to use
- Check if custom ISO upload supported
- Otherwise use Debian → NixOS kexec

### Dedirock

**Pros:**
- Competitive annual pricing
- Alternative to RackNerd

**Cons:**
- Less established (fewer reviews)
- Need to verify locations and reliability

**Deployment notes:**
- Test with 1 worker before bulk deployment
- Verify NixOS installation method

---

## Resources

- **LowEndBox**: https://lowendbox.com/ (VPS deals aggregator)
- **LowEndTalk**: https://lowendtalk.com/ (community forum, provider reviews)
- **ServerHunter**: https://www.serverhunter.com/ (price comparison tool)
- **RackNerd offers**: https://lowendbox.com/?s=racknerd (frequent deals)

---

## Next Steps

1. **Review current LowEndBox deals**: Check https://lowendbox.com/ for new providers
2. **Test RackNerd**: Order 1 Tokyo VPS ($10.18/year), deploy worker, monitor for 1 week
3. **Test nube.sh**: Order 1 Singapore VPS ($18/year), compare with RackNerd
4. **Document results**: Update `/openspec/changes/add-regional-monitoring-workers/specs/cheap-workers/spec.md`
5. **Scale if successful**: Deploy to 10 regions with 2-worker redundancy

---

**Last Updated**: 2025-10-30
**Status**: Research phase, no workers deployed yet
