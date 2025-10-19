# Oracle Cloud Free Tier Monitoring & Price Alerts

**Purpose**: Monitor Oracle Cloud Always Free tier to ensure India Strong node remains free
**Created**: 2025-10-19
**Node**: India Strong (Hyderabad)

---

## Current Oracle Free Tier Specs (India Strong)

### What We're Using

| Resource | Allocation | Value | Status |
|----------|-----------|-------|--------|
| **Compute** | VM.Standard.A1.Flex | 4 ARM cores, 24 GB RAM | Always Free |
| **Block Storage** | Boot Volume | 46 GB | Always Free |
| **Block Storage** | Block Volume | 99 GB | Always Free |
| **Total Storage** | | 145 GB | Always Free |
| **Network** | Bandwidth | 10 TB/month outbound | Always Free |
| **Location** | | Hyderabad (ap-hyderabad-1) | Always Free |

### Official Always Free Limits

Per Oracle's Always Free program:
- **Compute**: Up to 4 ARM cores + 24 GB RAM (VM.Standard.A1.Flex)
- **Storage**: Up to 200 GB total block storage
- **Network**: 10 TB outbound per month
- **Instances**: Up to 4 instances total

**Official Page**: https://www.oracle.com/cloud/free/

---

## Price Alert Setup

### Method 1: Oracle Cloud Console (Built-in)

**Steps:**
1. Login to Oracle Cloud Console
2. Go to **Governance & Administration** → **Cost Management** → **Budgets**
3. Create Budget Alert:
   ```
   Name: India-Strong-Free-Tier-Alert
   Target: Compartment (select your compartment)
   Alert Rule:
   - Type: Actual Spend
   - Threshold: $1.00 (any non-zero cost)
   - Email: your-email@example.com
   ```

4. Save and verify email notification

**Result**: Get alerted if Oracle charges anything for this node

---

### Method 2: External Monitoring Services

#### Option A: ChangeTower (Free)
- **URL**: https://changetower.com
- **Monitor**: https://www.oracle.com/cloud/free/
- **Alert on**: "Always Free" pricing changes
- **Frequency**: Daily
- **Notification**: Email

**Setup**:
```
1. Sign up at changetower.com (free tier)
2. Add URL: https://www.oracle.com/cloud/free/
3. Select keywords to monitor: "Always Free", "VM.Standard.A1"
4. Set notification email
```

#### Option B: Visualping (Free Tier)
- **URL**: https://visualping.io
- **Monitor**: Oracle Free Tier page
- **Alert on**: Text changes
- **Frequency**: Daily

#### Option C: Distill Web Monitor (Chrome Extension)
- **Install**: Chrome Web Store
- **Monitor**: Oracle pricing page
- **Alert**: Browser notification + email

---

### Method 3: RSS/Atom Feed Monitoring

**Oracle Cloud Blog RSS**:
- URL: https://blogs.oracle.com/cloud-infrastructure/rss
- Monitor for keywords: "Always Free", "pricing change", "A1 Flex"
- Use: Feedly, Inoreader, or custom RSS monitor

---

### Method 4: Social Media Alerts

**Twitter/X Monitoring**:
```
Search: (@Oracle OR @OracleCloud) (free tier OR always free OR A1)
Tools:
- TweetDeck
- Google Alerts for "Oracle Cloud Always Free tier"
- Reddit r/oraclecloud monitoring
```

**Reddit**:
- Subreddit: r/oraclecloud
- Search: "always free" + "price" + "change"
- Use: Reddit alerts or IFTTT

---

## Backup Plan (If Oracle Charges)

### If Oracle Starts Charging for India Strong:

**Option 1: Migrate to Netcup**
```
Cost: +$7.11/month (VPS 1000 ARM G11)
Storage: 256 GB (vs 145 GB) ✅
Impact: +$7/month = Total $25.42/month
```

**Option 2: Migrate to OVH**
```
Cost: +$6.75/month (VPS-2)
Storage: 100 GB (vs 145 GB) ⚠️ Need to reduce
Impact: +$7/month = Total $25.42/month
```

**Option 3: Remove India Strong entirely**
```
Cost: $0 (keep India Weak only)
Impact:
- Lose PostgreSQL replica in APAC
- India reads go to Germany (150ms latency)
- Still have 4 nodes (Germany, Austria, Canada, India Weak)
- etcd still 5 nodes (keep odd number)
Total: $18.42/month (no change)
```

---

## Migration Checklist (If Needed)

### Pre-Migration

- [ ] Verify Oracle is actually charging (check invoice)
- [ ] Calculate actual cost vs. migration cost
- [ ] Choose migration target (Netcup, OVH, or remove)
- [ ] Notify team of upcoming change

### Migration Steps

**If migrating to paid provider:**
1. [ ] Provision new node (Netcup or OVH)
2. [ ] Install Tailscale, get IP
3. [ ] Deploy PostgreSQL replica
4. [ ] Join to Patroni cluster
5. [ ] Verify replication lag < 100ms
6. [ ] Update all app nodes to use new replica IP
7. [ ] Monitor for 24 hours
8. [ ] Decommission Oracle node
9. [ ] Update documentation

**If removing India Strong:**
1. [ ] Update app configs (remove India replica)
2. [ ] Remove from Patroni cluster
3. [ ] Update documentation
4. [ ] Shutdown Oracle instance

---

## Cost Impact Scenarios

| Scenario | Monthly Cost | Annual Cost | Difference |
|----------|-------------|-------------|------------|
| **Current (Free)** | $18.42 | $221 | Baseline |
| **Oracle charges $10/mo** | $28.42 | $341 | +$120/year |
| **Migrate to Netcup** | $25.53 | $306 | +$85/year |
| **Remove India Strong** | $18.42 | $221 | $0 (no change) |

**Recommendation**: If Oracle charges more than $7/month, migrate to Netcup (better value, more storage).

---

## Monitoring Dashboard

### Weekly Checks

- [ ] Check Oracle Cloud billing dashboard
- [ ] Verify "Always Free" badge still shows
- [ ] Review any Oracle emails about policy changes

### Monthly Checks

- [ ] Review full Oracle invoice (should be $0.00)
- [ ] Check Oracle blog for announcements
- [ ] Verify instance still tagged as "Always Free"

### Quarterly Checks

- [ ] Review Oracle Free Tier documentation
- [ ] Check if limits changed (4 cores, 24 GB RAM, 200 GB storage)
- [ ] Test backup migration plan

---

## Alert Contacts

**Primary Contact**: [Your Email]
**Secondary Contact**: [Team Email]
**Slack Channel**: #infrastructure-alerts

**Alert Triggers**:
1. Oracle billing > $0.00
2. Oracle Free Tier page changes
3. Oracle Cloud blog mentions "Always Free" pricing
4. Reddit/Twitter mentions Oracle charging for free tier

---

## Important Links

- **Oracle Free Tier**: https://www.oracle.com/cloud/free/
- **Oracle Billing**: https://cloud.oracle.com/billing
- **Oracle Blog**: https://blogs.oracle.com/cloud-infrastructure/
- **Oracle Support**: https://www.oracle.com/support/
- **r/oraclecloud**: https://reddit.com/r/oraclecloud

---

## Historical Context

**2019-09-16**: Oracle announced Always Free tier
**2021-12-01**: Added ARM-based A1 instances to Always Free
**2025-10-19**: Currently using for India Strong node (free)

**Known Changes**:
- Oracle has NOT changed Always Free pricing since launch
- ARM A1 instances remain free as of 2025-10-19
- Many users report accounts terminated for "misuse" (monitor ToS compliance)

---

## Risk Assessment

**Likelihood of Oracle Charging**: **LOW**
- Always Free tier is a marketing tool for Oracle
- No precedent of changing free tier to paid
- ARM A1 instances are less profitable (encourage paid AMD/Intel upgrades)

**Impact if Oracle Charges**: **LOW**
- Easy migration options available
- Can remove node entirely with minimal impact
- Only $7-10/month increase if we migrate

**Mitigation**: Set up alerts (done via this doc) ✅

---

**Last Updated**: 2025-10-19
**Next Review**: 2025-11-19 (monthly)
**Status**: ✅ Active Monitoring
