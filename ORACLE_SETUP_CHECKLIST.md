# Oracle Cloud Setup Checklist - India Strong Node

## Quick Setup in 5 Minutes

### Step 1: Instance Status
- [ ] Go to **Compute → Instances**
- [ ] Find: **uptrack-node-india-strong**
- [ ] State: **RUNNING** (if STOPPED, click Start)
- [ ] Public IPv4: `144.24.133.171` ← Note this IP

---

### Step 2: Virtual Cloud Network (VCN)
- [ ] Go to **Networking → Virtual Cloud Networks**
- [ ] VCN exists: ✓
- [ ] VCN name: ________________
- [ ] VCN CIDR: ________________ (e.g., 10.0.0.0/16)

---

### Step 3: Internet Gateway
- [ ] Go to **Networking → Internet Gateways**
- [ ] Internet Gateway exists: ✓
- [ ] Status: **Available**
- [ ] Attached to VCN: ✓

---

### Step 4: Route Table
- [ ] Go to **Networking → Route Tables**
- [ ] Route Table exists for your VCN: ✓
- [ ] Has route: **0.0.0.0/0 → Internet Gateway** ✓

**If not, add it:**
1. Click **Add Route Rule**
2. Destination CIDR: `0.0.0.0/0`
3. Target Type: Internet Gateway
4. Target: Select your Internet Gateway
5. Click **Add Route Rule**

---

### Step 5: Security List (Firewall Rules)
- [ ] Go to **Networking → Virtual Cloud Networks**
- [ ] Select your VCN
- [ ] Find **Security Lists**
- [ ] Click on default security list

**Add Ingress Rules:**

#### SSH (Required for NixOS installation)
- [ ] Protocol: TCP
- [ ] Source CIDR: `0.0.0.0/0`
- [ ] Port: `22`
- [ ] Click **Add Ingress Rule**

#### HTTP (Optional, for web access)
- [ ] Protocol: TCP
- [ ] Source CIDR: `0.0.0.0/0`
- [ ] Port: `80`
- [ ] Click **Add Ingress Rule**

#### HTTPS (Optional, for web access)
- [ ] Protocol: TCP
- [ ] Source CIDR: `0.0.0.0/0`
- [ ] Port: `443`
- [ ] Click **Add Ingress Rule**

#### Phoenix App (Internal)
- [ ] Protocol: TCP
- [ ] Source CIDR: `0.0.0.0/0` (or just `10.0.0.0/16`)
- [ ] Port: `4000`
- [ ] Click **Add Ingress Rule**

**Then click: Save Security List Rules**

---

### Step 6: Instance VNIC Configuration
- [ ] Go to **Compute → Instances**
- [ ] Click your instance name
- [ ] Scroll to **Primary VNIC Information**
- [ ] Public IPv4 Address: `144.24.133.171` ✓

**If NO Public IP:**
1. Click on the VNIC name (in Primary VNIC section)
2. Go to **IPv4 Addresses**
3. Click **Assign Public IPv4 Address**
4. Select type (Ephemeral = temporary, Reserved = permanent)
5. Click **Assign**

---

### Step 7: Subnet Configuration
- [ ] Go to **Networking → Subnets**
- [ ] Your subnet exists: ✓
- [ ] Associated with your VCN: ✓
- [ ] Route Table: Configured with Internet Gateway: ✓
- [ ] Security List: Has SSH rule: ✓

---

## Test Connectivity

After completing all steps above:

### Test 1: Ping
```bash
ping 144.24.133.171
```

**Expected**: Responses like `64 bytes from 144.24.133.171: icmp_seq=0 ttl=50 time=150.000 ms`

**If timeout**: Go back to checklist, verify Internet Gateway and Route Table

---

### Test 2: SSH
```bash
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

**Expected**: Ubuntu shell prompt or SSH banner

**If timeout**: Check Security List has SSH rule (port 22)

**If "Permission denied"**: SSH key not authorized - verify in instance metadata

---

## Troubleshooting

### Problem 1: Still Can't Ping
- [ ] Instance state = RUNNING?
- [ ] Internet Gateway attached to VCN?
- [ ] Route Table has route 0.0.0.0/0 → Internet Gateway?

### Problem 2: SSH Times Out After Ping Works
- [ ] Security List has TCP port 22 rule?
- [ ] Source CIDR is 0.0.0.0/0 (or your IP)?

### Problem 3: SSH "Permission Denied"
- [ ] SSH key authorized in instance? (Instance → SSH Keys)
- [ ] SSH key permissions correct? (chmod 400)
- [ ] Connecting as **ubuntu** user (not root)?

### Problem 4: Instance Not Reachable
- [ ] Click instance → Reboot Instance
- [ ] Wait 2-3 minutes for reboot to complete
- [ ] Try ping again

---

## Most Common Issues

| Issue | Fix |
|-------|-----|
| Ping timeout | Check Internet Gateway attached & Route Table configured |
| SSH timeout (ping works) | Add TCP port 22 to Security List |
| Permission denied | Authorize SSH key in instance metadata |
| Instance won't start | Check Oracle credits/quotas haven't been exceeded |

---

## After Connectivity Works

Once you can SSH successfully:

```bash
# Verify Ubuntu
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
uname -a
# Should show: ... aarch64 GNU/Linux

# Proceed with NixOS installation
# See: INSTALL_NIXOS_INDIA_STRONG.md
```

---

## Network Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Instance | _______ | Running? |
| VCN | _______ | Created & CIDR noted? |
| Internet Gateway | _______ | Attached? |
| Route Table | _______ | Has 0.0.0.0/0 → IGW? |
| Security List | _______ | Has SSH (port 22)? |
| Public IP | _______ | Assigned to instance? |
| Ping Test | _______ | Works? |
| SSH Test | _______ | Works? |

---

**Next**: After everything is ✓, proceed with NixOS installation in INSTALL_NIXOS_INDIA_STRONG.md

