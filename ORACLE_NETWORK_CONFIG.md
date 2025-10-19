# Oracle Cloud Networking Configuration for India Strong Node

## Overview

For your instance to be reachable from your MacBook, you need to configure:

1. **Virtual Cloud Network (VCN)** - Network isolation
2. **Internet Gateway** - Route to internet
3. **Route Table** - Defines how traffic flows
4. **Network Security Group (NSG)** or **Security List** - Firewall rules
5. **Public IP Address** - Assigned to your instance

---

## Step 1: Create/Verify Virtual Cloud Network (VCN)

### In Oracle Cloud Console:

1. Go to **Networking → Virtual Cloud Networks**
2. Look for your VCN (or create one):
   - **Name**: e.g., "uptrack-vcn"
   - **CIDR Block**: e.g., "10.0.0.0/16"

**If VCN doesn't exist**, create it:
- Click **Start VCN Wizard**
- Select **VCN with Internet Connectivity**
- Accept defaults
- Click **Create**

---

## Step 2: Create/Verify Internet Gateway

### In Oracle Cloud Console:

1. Go to **Networking → Internet Gateways**
2. Verify an Internet Gateway exists for your VCN
3. **Status** should be **Available**

**If doesn't exist**, create it:
1. Click **Create Internet Gateway**
2. Name: e.g., "uptrack-igw"
3. Select your VCN
4. Click **Create**

**Attach to VCN if not already attached:**
- Select the Internet Gateway
- Click **Attach to VCN**
- Choose your VCN
- Click **Attach**

---

## Step 3: Configure Route Table

### In Oracle Cloud Console:

1. Go to **Networking → Route Tables**
2. Select the route table for your subnet (usually default)
3. Click **Add Route Rule**

### Add Route Rule for Internet Traffic:

| Field | Value |
|-------|-------|
| **Destination CIDR Block** | `0.0.0.0/0` (All internet traffic) |
| **Target Type** | Internet Gateway |
| **Target Internet Gateway** | Select your Internet Gateway (e.g., "uptrack-igw") |

**Steps:**
1. Click **Add Route Rule**
2. Fill in the values above
3. Click **Add Route Rule** (button at bottom)

**Expected Result:**
```
Destination CIDR    | Target Type        | Target
0.0.0.0/0          | Internet Gateway   | uptrack-igw
```

---

## Step 4: Configure Network Security Group (NSG) or Security List

### For Security List (simpler):

1. Go to **Networking → Virtual Cloud Networks**
2. Select your VCN
3. Find **Security Lists** section
4. Click on the default security list

### Add Ingress Rules:

Add these rules to allow SSH and other services:

#### Rule 1: SSH (Port 22)
| Field | Value |
|-------|-------|
| **Stateless** | No (checked) |
| **Protocol** | TCP |
| **Source CIDR** | `0.0.0.0/0` (Allow all IPs) |
| **Destination Port** | `22` |
| **Description** | SSH access |

#### Rule 2: HTTP (Port 80)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `0.0.0.0/0` |
| **Destination Port** | `80` |
| **Description** | HTTP |

#### Rule 3: HTTPS (Port 443)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `0.0.0.0/0` |
| **Destination Port** | `443` |
| **Description** | HTTPS |

#### Rule 4: Phoenix App (Port 4000)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `0.0.0.0/0` |
| **Destination Port** | `4000` |
| **Description** | Phoenix app |

#### Rule 5: PostgreSQL (Port 5432)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `10.0.0.0/16` (Internal network only) |
| **Destination Port** | `5432` |
| **Description** | PostgreSQL (internal) |

#### Rule 6: Patroni (Port 8008)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `10.0.0.0/16` (Internal only) |
| **Destination Port** | `8008` |
| **Description** | Patroni REST API |

#### Rule 7: etcd Client (Port 2379)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `10.0.0.0/16` (Internal only) |
| **Destination Port** | `2379` |
| **Description** | etcd client |

#### Rule 8: etcd Peer (Port 2380)
| Field | Value |
|-------|-------|
| **Stateless** | No |
| **Protocol** | TCP |
| **Source CIDR** | `10.0.0.0/16` (Internal only) |
| **Destination Port** | `2380` |
| **Description** | etcd peer |

**Steps to add rule:**
1. Click **Add Ingress Rule**
2. Fill in the values
3. Click **Another Ingress Rule** to add more
4. Click **Save Security List Rules**

---

## Step 5: Verify Instance Has Public IP

### In Oracle Cloud Console:

1. Go to **Compute → Instances**
2. Click on your instance name
3. Scroll to **Primary VNIC Information**
4. Verify **Public IPv4 Address** is assigned
   - Should see an IP like `144.24.133.171`

**If no public IP:**
1. Click on the VNIC (network interface)
2. Go to **IPv4 Addresses**
3. Click **Assign Public IPv4 Address**
4. Select "Ephemeral (temporary)" or "Reserved (permanent)"
5. Click **Assign**

---

## Step 6: Verify Subnet is Configured Correctly

### In Oracle Cloud Console:

1. Go to **Networking → Subnets**
2. Find the subnet where your instance is running
3. Verify:
   - **CIDR Block**: Should be part of VCN CIDR (e.g., 10.0.0.0/24)
   - **Route Table**: Should have route to Internet Gateway
   - **Security List**: Should have SSH and other rules

**If subnet is not configured:**
1. Click **Create Subnet**
2. **VCN**: Select your VCN
3. **Name**: e.g., "uptrack-subnet"
4. **CIDR Block**: e.g., "10.0.1.0/24"
5. **Route Table**: Select the one with Internet Gateway route
6. **Security List**: Select the one with SSH rule
7. Click **Create**

---

## Step 7: Test Connectivity

After configuring all the above:

```bash
# Test ping (from your MacBook)
ping 144.24.133.171

# Should see responses (not timeouts):
# PING 144.24.133.171 (144.24.133.171): 56 data bytes
# 64 bytes from 144.24.133.171: icmp_seq=0 ttl=50 time=150.000 ms
```

If ping works, try SSH:

```bash
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

---

## Complete Networking Diagram

```
Your MacBook (Home/Office)
        ↓ (SSH to 144.24.133.171)
Internet Gateway (uptrack-igw)
        ↓ (Route 0.0.0.0/0)
Route Table
        ↓ (Security List rules allow port 22)
Network Security Group
        ↓
Subnet (10.0.1.0/24)
        ↓
Instance (uptrack-node-india-strong)
        ↓
Primary VNIC with Public IP (144.24.133.171)
```

---

## Oracle Cloud Console Navigation Quick Reference

| What | Where |
|------|-------|
| VCN Setup | Networking → Virtual Cloud Networks |
| Internet Gateway | Networking → Internet Gateways |
| Route Tables | Networking → Route Tables |
| Security Lists | Networking → Virtual Cloud Networks → Subnets → Security Lists |
| Network Security Groups | Networking → Network Security Groups |
| Instances | Compute → Instances |
| Public IPs | Networking → Public IP Addresses |

---

## Checklist: Before Testing SSH

- [ ] Instance state = **RUNNING** (Compute → Instances)
- [ ] Instance has **Public IPv4 Address** assigned
- [ ] VCN exists and is associated with the instance
- [ ] Internet Gateway exists and is **Available**
- [ ] Route Table has rule: `0.0.0.0/0 → Internet Gateway`
- [ ] Security List has Ingress rule: `TCP port 22 from 0.0.0.0/0`
- [ ] Subnet is configured and associated with instance
- [ ] Network is fully deployed (may take ~2 minutes)

---

## If Still Not Working

### Debugging Steps:

1. **Verify instance VNIC details:**
   - Go to instance details
   - Click on the VNIC name
   - Check IPv4 addresses and security groups

2. **Check instance event logs:**
   - In instance details, go to **Work Requests**
   - Look for any errors during creation

3. **Try telnet to test port 22:**
   ```bash
   telnet 144.24.133.171 22
   # Should show SSH banner like: SSH-2.0-OpenSSH_8.2...
   ```

4. **Check if instance needs reboot:**
   - Reboot the instance: Compute → Instances → Reboot

5. **Verify SSH key is authorized:**
   - SSH key must be in Oracle metadata
   - Check: Instance Details → SSH Keys

---

## References

- [Oracle VCN Documentation](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/overview.htm)
- [Security Lists](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/securitylists.htm)
- [Internet Gateway](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingIGs.htm)
- [Route Tables](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingroutetables.htm)

---

**Status**: Networking configuration guide
**Last Updated**: 2025-10-19
