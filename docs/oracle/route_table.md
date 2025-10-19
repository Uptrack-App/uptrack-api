# Oracle Cloud Route Table Configuration

## Overview

Route Tables in Oracle Cloud define how network traffic flows within your Virtual Cloud Network (VCN). They are essential for connecting your instances to the Internet Gateway.

---

## Understanding Route Tables

### What is a Route Table?

A Route Table is a set of rules (called routes) that determine where network traffic from your subnet is directed.

**Example Route Rule:**
```
Destination CIDR: 0.0.0.0/0          (All internet traffic)
Target Type: Internet Gateway        (Route to Internet Gateway)
Target: igw-uptrack-ch-pri          (The specific Internet Gateway)
```

This rule means: "Any traffic going to the internet (0.0.0.0/0) should go through the Internet Gateway."

---

## Default Route Table Restrictions

### The API Error

When you try to add a route to the **Default Route Table**, you may see:

```
⚠️ API Error
Rules in the route table must use private IP as a target.
Or the route table can be empty (no rules).
```

### Why This Happens

Oracle Cloud's **Default Route Table** has special restrictions:

1. **Created automatically** when you create a VCN
2. **Cannot be deleted** - it's managed by Oracle
3. **Restrictive rules** - only allows private IP targets in some cases
4. **Not recommended for public subnets** - should use custom route tables

### The Workaround

**Do NOT use the Default Route Table for public subnets.**

Instead:
1. ✅ Create a **new, custom Route Table**
2. ✅ Configure it with Internet Gateway routes
3. ✅ Associate it with your public subnet

---

## Step-by-Step: Fix Route Table Configuration

### Step 1: Identify the Problem

Check if your subnet is using the **Default Route Table**:

1. Go to **Networking → Subnets**
2. Click on your subnet (e.g., `sb-uptrack-ch-pri`)
3. Look at **Route Table** field
4. If it says "Default Route Table for vcn-...", you found the problem ❌

### Step 2: Create a Custom Route Table

1. Go to **Networking → Route Tables**
2. Click **Create Route Table**
3. Fill in:
   - **Name**: `public-route-table-uptrack` (or any name)
   - **VCN**: Select your VCN (`vcn-uptrack-ch-pri`)
   - **Compartment**: Select your compartment
4. Click **Create Route Table**

**Expected Result:**
- New route table created
- Status: **Active**
- Initially has **no route rules**

### Step 3: Add Internet Gateway Route

After creating the route table:

1. Click on the newly created route table
2. Click **Add Route Rules**
3. Fill in:
   - **Target Type**: `Internet Gateway`
   - **Destination CIDR Block**: `0.0.0.0/0`
   - **Target Internet Gateway**: Select your Internet Gateway (e.g., `igw-uptrack-ch-pri`)
   - **Description** (optional): `Route to Internet`
4. Click **Add Route Rule**

**Expected Result:**
- Route rule created successfully ✅
- Status shows in the route table

### Step 4: Associate Route Table with Public Subnet

Now link the custom route table to your subnet:

1. Go to **Networking → Subnets**
2. Click on your public subnet (e.g., `sb-uptrack-ch-pri`)
3. Scroll down to **Route Table** section
4. Click **Change Route Table** (or **Edit** if available)
5. Select your new custom route table (`public-route-table-uptrack`)
6. Click **Change** or **Save**

**Expected Result:**
- Subnet now uses your custom route table ✅
- Route rules now apply to traffic from this subnet

---

## Complete Networking Flow

```
Instance (10.0.0.198)
    ↓ (needs to reach internet)
Subnet (sb-uptrack-ch-pri)
    ↓ (has associated route table)
Route Table (public-route-table-uptrack)
    ↓ (checks destination against route rules)
Route Rule: 0.0.0.0/0 → Internet Gateway
    ↓ (matches: all internet traffic)
Internet Gateway (igw-uptrack-ch-pri)
    ↓ (attached to VCN)
Internet ✅
```

---

## Troubleshooting Route Table Issues

### Problem 1: API Error When Adding Route to Default Route Table

**Error:**
```
Rules in the route table must use private IP as a target.
```

**Solution:**
- ✅ Create a new, custom Route Table (don't use Default)
- ✅ Associate it with your subnet
- ✅ Add routes to the custom table

### Problem 2: Instance Still Can't Reach Internet After Adding Route

**Check:**
1. Instance has **Public IP** assigned ✓
2. Route table is **associated with the subnet** ✓
3. Route rule **0.0.0.0/0 → Internet Gateway** exists ✓
4. **Security List** allows **outbound traffic** ✓
5. **Internet Gateway** is **attached to VCN** ✓

### Problem 3: Route Table Shows Empty After Creation

**This is normal!**
- Route tables start empty (no rules)
- You must manually add route rules
- Click **Add Route Rules** to add them

### Problem 4: Can't Find Internet Gateway in Dropdown

**This means:**
- Internet Gateway not created yet
- Or not attached to the VCN
- Or in a different compartment

**Solution:**
1. Create an Internet Gateway if needed
2. Attach it to your VCN
3. Wait a few seconds for it to appear in dropdowns

---

## Route Table Best Practices

### For Public Subnets (instances needing internet access)

✅ **Route Table Should Contain:**
```
Destination: 0.0.0.0/0
Target: Internet Gateway
```

### For Private Subnets (internal only)

✅ **Route Table Should Contain:**
```
Destination: 10.0.0.0/16 (your VCN CIDR)
Target: Local
```
(Usually created automatically)

### For NAT Gateway (private subnet with outbound internet)

✅ **Route Table Should Contain:**
```
Destination: 0.0.0.0/0
Target: NAT Gateway
```

---

## Route Table Naming Conventions

Use consistent naming for easy management:

| Purpose | Name Pattern |
|---------|--------------|
| Public subnet routes | `public-route-table-[name]` |
| Private subnet routes | `private-route-table-[name]` |
| Database subnet routes | `db-route-table-[name]` |
| Management subnet routes | `mgmt-route-table-[name]` |

**Example:**
- `public-route-table-uptrack` ✅
- `private-route-table-uptrack` ✅
- `db-route-table-uptrack-pg` ✅

---

## Key Takeaways

1. **Default Route Table has limitations** - Don't use it for public subnets
2. **Create custom Route Tables** for public subnets
3. **Add 0.0.0.0/0 → Internet Gateway route** for internet access
4. **Associate Route Table with Subnet** to apply the rules
5. **Verify all components** (IGW attached, route rules exist, security list allows traffic)

---

## Quick Reference Commands

### View Route Tables
```bash
# Via Oracle Console:
Networking → Route Tables
```

### Typical Public Subnet Route Table
```
Route Rule 1:
├─ Destination CIDR: 0.0.0.0/0
├─ Target Type: Internet Gateway
└─ Target: igw-uptrack-ch-pri
```

### Typical Private Subnet Route Table
```
Route Rule 1:
├─ Destination CIDR: 10.0.0.0/16
├─ Target Type: Local
└─ Target: Local Peering Gateway (VCN Local)
```

---

## Related Documentation

- [Oracle Route Tables Documentation](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingroutetables.htm)
- [Internet Gateway Setup](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingIGs.htm)
- [VCN Concepts](https://docs.oracle.com/en-us/iaas/Content/Network/Concepts/overview.htm)

---

**Last Updated**: 2025-10-19
**Status**: Ready for India Strong deployment
