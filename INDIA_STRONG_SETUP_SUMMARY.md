# India Strong Node Setup - Complete Summary

## Current Status: 🔴 Network Unreachable

**Problem**: Cannot reach Oracle instance at 144.24.133.171

**Root Cause**: Networking not properly configured in Oracle Cloud Console

**Time to Fix**: ~5-10 minutes

---

## What You Need to Do (Right Now)

### Step 1: Open Oracle Cloud Console

Go to: **https://cloud.oracle.com/**

### Step 2: Follow the Checklist

Use the **5-minute checklist**: `/Users/le/repos/uptrack/ORACLE_SETUP_CHECKLIST.md`

This will guide you to configure:
- ✅ Virtual Cloud Network (VCN)
- ✅ Internet Gateway
- ✅ Route Table (0.0.0.0/0 → Internet Gateway)
- ✅ Security List (SSH port 22 ingress rule)
- ✅ Public IP assignment

### Step 3: Test Connectivity

After configklist is complete:

```bash
# Test ping
ping 144.24.133.171

# Test SSH
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

---

## Documentation Files Created

I've created comprehensive guides for you:

| File | Purpose | Use When |
|------|---------|----------|
| **ORACLE_SETUP_CHECKLIST.md** | Quick 5-minute network setup | Setting up Oracle networking |
| **ORACLE_NETWORK_CONFIG.md** | Detailed networking guide | Need deep understanding of networking |
| **INSTALL_NIXOS_INDIA_STRONG.md** | Complete NixOS installation | After network is working |
| **INDIA_STRONG_DEBUG.md** | Troubleshooting SSH issues | If connectivity still fails |

---

## Quick Networking Overview

For your MacBook to reach the Oracle instance:

```
Your MacBook
    ↓ (SSH to 144.24.133.171)
Internet
    ↓
Oracle Cloud Region (ap-mumbai-1)
    ↓
Internet Gateway (allows internet traffic)
    ↓
Route Table (routes 0.0.0.0/0 to Internet Gateway)
    ↓
Security List (firewall - allows port 22)
    ↓
VCN Subnet (10.0.x.0/24)
    ↓
Instance with Public IP (144.24.133.171)
```

**Each arrow must be configured!** If any step is missing, connectivity fails.

---

## Key Oracle Cloud Networking Concepts

### 1. Virtual Cloud Network (VCN)
- Like a private network in the cloud
- Example CIDR: 10.0.0.0/16
- All your resources live here

### 2. Internet Gateway (IGW)
- Connects VCN to the internet
- Must be **attached** to your VCN
- Must be in **Available** state

### 3. Route Table
- Defines how traffic flows
- Must have: `0.0.0.0/0 → Internet Gateway`
- This says: "Any traffic to the internet goes through IGW"

### 4. Security List (Firewall)
- Controls what traffic is allowed
- Must have **Ingress Rule**: TCP port 22 from 0.0.0.0/0 (SSH)
- Without this, SSH will timeout

### 5. Public IP
- Instance's address on the internet (144.24.133.171)
- Must be **assigned** to the instance
- Must be in the same VCN/Subnet as instance

### 6. Subnet
- Subdivision of VCN
- Example CIDR: 10.0.1.0/24
- Instance runs inside a subnet

---

## The Setup Path

```
START
  ↓
[1] Oracle Cloud Console Open?
  ↓ YES
[2] Instance Running?
  ↓ YES
[3] VCN Created?
  ↓ YES
[4] Internet Gateway Attached?
  ↓ YES
[5] Route Table Configured (0.0.0.0/0 → IGW)?
  ↓ YES
[6] Security List Has SSH Rule (Port 22)?
  ↓ YES
[7] Public IP Assigned to Instance?
  ↓ YES
[8] Ping Test Works?
  ↓ YES
[9] SSH Test Works?
  ↓ YES
READY FOR NixOS INSTALLATION ✅
  ↓
See: INSTALL_NIXOS_INDIA_STRONG.md
```

---

## What Happens After Network Works

Once you can SSH:

### 1. Prepare NixOS Installation
```bash
cd /Users/le/repos/uptrack
chmod 400 /Users/le/.ssh/ssh-key-2025-10-18.key
```

### 2. Run NixOS Installation (takes 10-15 minutes)
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i /Users/le/.ssh/ssh-key-2025-10-18.key \
  root@144.24.133.171
```

### 3. Deploy Application (Colmena)
```bash
colmena apply --on node-india-strong
```

### 4. Verify Services
```bash
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
sudo systemctl status postgresql patroni etcd uptrack-app
```

---

## Common Mistakes to Avoid

❌ **Mistake 1**: Forgetting to attach Internet Gateway to VCN
- **Fix**: In Internet Gateways page, click your IGW → Attach to VCN

❌ **Mistake 2**: Not adding route to Route Table
- **Fix**: Route Table should have: `0.0.0.0/0 → Internet Gateway`

❌ **Mistake 3**: Security List doesn't have SSH rule
- **Fix**: Add Ingress Rule: TCP port 22 from 0.0.0.0/0

❌ **Mistake 4**: Instance doesn't have Public IP
- **Fix**: Go to instance VNIC → IPv4 Addresses → Assign Public IPv4 Address

❌ **Mistake 5**: Instance not in the VCN with Internet Gateway
- **Fix**: Verify instance's Primary VNIC is in correct subnet/VCN

---

## Support Documents

If you get stuck:

1. **For networking questions**: See `ORACLE_NETWORK_CONFIG.md`
2. **For quick setup**: Use `ORACLE_SETUP_CHECKLIST.md`
3. **For SSH issues**: See `INDIA_STRONG_DEBUG.md`
4. **For NixOS installation**: See `INSTALL_NIXOS_INDIA_STRONG.md`

---

## Timeline Estimate

| Task | Time |
|------|------|
| Configure Oracle networking | 5-10 min |
| Test connectivity | 2 min |
| NixOS installation | 10-15 min |
| Services deployment | 5-10 min |
| Verification | 5 min |
| **Total** | **~40 minutes** |

---

## Next Step

👉 **Open Oracle Cloud Console and follow**: `ORACLE_SETUP_CHECKLIST.md`

After that works, come back and I'll help with NixOS installation!

---

**Status**: Waiting for network configuration
**Created**: 2025-10-19
**Node IP**: 144.24.133.171
**SSH Key**: ssh-key-2025-10-18.key
