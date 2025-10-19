# India Strong Node - SSH Connection Debug Guide

## Issue: `Operation timed out` when SSH to 144.24.133.171

The ping test shows **100% packet loss**, meaning the server is not reachable over the network.

---

## Diagnostic Steps

### Step 1: Check if Instance is Running

Go to **Oracle Cloud Console**:

1. Navigate to: **Compute > Instances**
2. Find: **uptrack-node-india-strong** or similar name
3. Check the **State** field:
   - ✅ **RUNNING** = Instance is on
   - ❌ **STOPPED** = Need to start it
   - ⚠️ **PROVISIONING** = Still booting up

**If STOPPED, click "Start" to turn on the instance.**

### Step 2: Verify Public IP Address

In Oracle Cloud Console:

1. Click on the instance name
2. Look for **Public IPv4 Address**
3. Confirm it matches: `144.24.133.171`
4. If different, update the SSH command with the correct IP

**Current IP we're trying**: `144.24.133.171`

### Step 3: Check Network Security Rules

In Oracle Cloud Console:

1. Go to: **Networking > Virtual Cloud Networks**
2. Find your VCN (Virtual Cloud Network)
3. Find **Security Lists** or **Network Security Groups**
4. Check **Ingress Rules** for port 22 (SSH):
   - Should allow: **TCP port 22 from 0.0.0.0/0** (or your IP range)
   - If missing, click "Add Rule" and add SSH rule

### Step 4: Check Instance Details

In Oracle Cloud Console, click the instance and verify:

- **Image**: Should be Ubuntu 22.04 LTS ARM64
- **Shape**: Should be ARM64 (aarch64) - typically Ampere A1 Compute
- **Networking**: Check primary VNIC has a public IP
- **Boot Volume**: Should have a boot volume attached

### Step 5: Test Connectivity After Fixes

Once you've verified the above, try:

```bash
# Test connectivity
ping 144.24.133.171

# Should see responses like:
# 64 bytes from 144.24.133.171: icmp_seq=0 ttl=50 time=150.000 ms
```

Then try SSH:

```bash
# Test SSH
ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Should connect to Ubuntu shell
```

---

## Common Issues & Fixes

### Issue 1: Instance is STOPPED

**Fix**: Click "Start" in Oracle Cloud Console

**Time to start**: ~2-3 minutes

---

### Issue 2: Wrong IP Address

**Fix**:
1. Copy the correct **Public IPv4 Address** from Oracle Console
2. Update your SSH command
3. Try again

---

### Issue 3: SSH Port 22 Not Open in Firewall

**Fix**:
1. In Oracle Console, find the **Security List**
2. Add an **Ingress Rule**:
   - **Protocol**: TCP
   - **Source**: 0.0.0.0/0 (or your IP)
   - **Destination Port**: 22
3. Click "Add Ingress Rule"
4. Wait ~30 seconds for rule to apply
5. Try SSH again

---

### Issue 4: Wrong SSH Key

**Verify your key has correct permissions**:

```bash
# Check key permissions
ls -la /Users/le/.ssh/ssh-key-2025-10-18.key

# Should show: -rw------- (600 permissions)

# Fix if needed
chmod 600 /Users/le/.ssh/ssh-key-2025-10-18.key

# Try SSH with verbose output to see which key is being used
ssh -vv -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

---

### Issue 5: Instance Was Recently Created

If the instance was created in the last 10 minutes, it may still be booting.

**Fix**: Wait 5-10 minutes and try again

---

## What to Do Next

Once SSH is working:

1. **Verify Ubuntu is running**:
   ```bash
   ssh -i /Users/le/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
   uname -a
   # Should show: Linux ... aarch64 GNU/Linux
   ```

2. **Check disk and resources**:
   ```bash
   df -h           # Check disk space
   free -h         # Check RAM
   lscpu           # Check CPU
   lsblk           # Check block devices
   ```

3. **Become root**:
   ```bash
   sudo su -
   ```

4. **Run NixOS installation** (see INSTALL_NIXOS.md)

---

## Still Stuck?

If none of the above works:

1. **Check Oracle Cloud status page**: https://status.oracle.com/
2. **Check instance activity logs** in Oracle Console
3. **Restart the instance**: Stop → Start in Oracle Console
4. **Check SSH key was uploaded correctly**:
   ```bash
   cat /Users/le/.ssh/ssh-key-2025-10-18.key.pub
   # Copy this and paste into Oracle Console → Add SSH Key
   ```

---

**Last Updated**: 2025-10-19
**Status**: Troubleshooting network connectivity
