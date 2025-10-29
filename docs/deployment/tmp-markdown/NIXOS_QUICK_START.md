# NixOS Installation - Quick Start Guide

## 🚀 TL;DR - Run This Now

```bash
cd /Users/le/repos/uptrack
bash install-nixos-india-strong.sh
```

Done! The script will:
1. ✅ Verify all prerequisites
2. ✅ Confirm installation with you
3. ✅ Run nixos-anywhere (takes 10-15 min)
4. ✅ Wait for system to boot (5 min)
5. ✅ Verify everything is working
6. ✅ Show you what to do next

---

## What Gets Installed

✅ **NixOS 25.05** ARM64 - Declarative Linux OS (matches terra project)
✅ **PostgreSQL** - Database (replica mode)
✅ **Patroni** - PostgreSQL High Availability
✅ **etcd** - Distributed consensus (cluster coordination)
✅ **ClickHouse** - Time-series analytics database
✅ **Uptrack App** - Phoenix/Elixir monitoring application

---

## Prerequisites (Auto-Checked by Script)

- [x] SSH key at `~/.ssh/ssh-key-2025-10-18.key` with 600 permissions
- [x] Network connectivity to `144.24.133.171`
- [x] Nix installed on your MacBook
- [x] Repository at `/Users/le/repos/uptrack`
- [x] Flake configuration in repo

**The script checks all of these automatically!**

---

## One-Liner Installation

```bash
bash /Users/le/repos/uptrack/install-nixos-india-strong.sh
```

**Time Required**: ~25 minutes total
- Prerequisites check: 1 min
- nixos-anywhere: 10-15 min
- System boot: 5 min
- Verification: 2-3 min

---

## What Happens Step-by-Step

### Step 1: Verification (1 min)
```
[INFO] Checking SSH key exists
[INFO] Checking SSH key permissions
[INFO] Testing SSH connectivity
[INFO] Checking Nix installation
[INFO] Checking repo directory
[INFO] Checking flake configuration
✓ All prerequisites verified
```

### Step 2: Confirmation
```
⚠️  WARNING: This will install NixOS on 144.24.133.171
⚠️  WARNING: This WILL ERASE the disk!
⚠️  WARNING: This is IRREVERSIBLE!

Do you want to proceed? (yes/no): yes
Type the IP address to confirm (144.24.133.171): 144.24.133.171
Installation confirmed. Starting in 3 seconds...
```

### Step 3: Installation (10-15 min)
```
Starting nixos-anywhere...
[INFO] Uploading NixOS configuration...
[INFO] Downloading NixOS 24.11 ARM64 image...
[INFO] Partitioning disk...
[INFO] Installing NixOS base system...
[INFO] Applying node configurations...
[INFO] System will reboot now...
```

### Step 4: Boot Wait (5 min)
```
System is rebooting. Waiting 5 minutes for full boot...
[INFO] Waiting... 5m remaining
[INFO] Waiting... 4m remaining
[INFO] Waiting... 3m remaining
...
✓ Boot wait period completed
```

### Step 5: Verification
```
[INFO] NixOS version: NixOS 24.11
[INFO] Hostname: uptrack-node-india-strong
[INFO] System: Linux uptrack-node-india-strong ... aarch64 GNU/Linux
[INFO] Disk usage: [disk info]
[INFO] Memory: [memory info]
✓ NixOS installation verified
```

### Step 6: Service Check
```
[INFO] PostgreSQL: ✓ running
[INFO] Patroni: ✓ running
[INFO] etcd: ✓ running
[INFO] ClickHouse: ✓ running
```

### Step 7: Complete!
```
═══════════════════════════════════════════════════════════
NixOS Installation Complete! ✅
═══════════════════════════════════════════════════════════

Installation Summary:
  Server:  144.24.133.171
  Region:  ap-south-1 (India Hyderabad)
  OS:      NixOS 25.05
  Arch:    ARM64 (aarch64)

Next Steps:
  1. SSH to node:
     ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

  2. Check services:
     sudo systemctl status | grep -E 'postgresql|patroni|etcd|clickhouse'

  3. Deploy application:
     cd /Users/le/repos/uptrack
     colmena apply --on node-india-strong

  4. Monitor logs:
     sudo journalctl -u uptrack-app -f
```

---

## If Something Goes Wrong

### Script Can't Connect to Instance

**Error**: `Cannot connect to 144.24.133.171`

**Fix**:
1. Verify instance is RUNNING in Oracle Console
2. Check Internet Gateway is attached
3. Check Route Table has 0.0.0.0/0 → IGW route
4. Check Security List allows SSH port 22

See: `/Users/le/repos/uptrack/ORACLE_SETUP_CHECKLIST.md`

### SSH Key Permission Error

**Error**: `UNPROTECTED PRIVATE KEY FILE`

**Fix**:
```bash
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

See: `/Users/le/repos/uptrack/docs/ssh_key_permissions.md`

### Installation Timeout

**Error**: Installation takes >20 minutes or hangs

**Fix**:
1. Press Ctrl+C to stop
2. Wait 5 minutes (system may be booting)
3. Run again: `bash install-nixos-india-strong.sh`

### Services Not Running After Installation

**Error**: PostgreSQL/Patroni/etcd not running

**Fix**:
- Wait 2 more minutes (they may still be starting)
- Check logs: `ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171 journalctl -u postgresql`

---

## Manual Installation (If Script Fails)

If the automated script doesn't work, see detailed guide:

```bash
cat /Users/le/repos/uptrack/NIXOS_INSTALLATION.md
```

Manual command:
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  --extra-files ./infra/nixos/secrets \
  -i ~/.ssh/ssh-key-2025-10-18.key \
  root@144.24.133.171
```

---

## After Installation

### 1. SSH to Node

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
```

### 2. Check Services

```bash
sudo systemctl status | grep -E 'postgresql|patroni|etcd|clickhouse|uptrack'
```

### 3. Deploy Application

```bash
cd /Users/le/repos/uptrack
colmena apply --on node-india-strong
```

### 4. Monitor Logs

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
sudo journalctl -u uptrack-app -f
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `install-nixos-india-strong.sh` | Automated installation script |
| `NIXOS_INSTALLATION.md` | Detailed installation guide |
| `ORACLE_SETUP_CHECKLIST.md` | Oracle networking checklist |
| `docs/oracle/route_table.md` | Route Table documentation |
| `docs/ssh_key_permissions.md` | SSH key permissions guide |

---

## Important Notes

✅ **This is safe**: Script verifies everything before installation
✅ **This is fast**: ~25 minutes total (most is waiting for boot)
✅ **This is reversible**: Just reinstall if something goes wrong
⚠️ **This erases the disk**: All data on the instance will be lost
⚠️ **Confirm carefully**: The script asks you to confirm twice

---

## Ready to Go?

```bash
bash /Users/le/repos/uptrack/install-nixos-india-strong.sh
```

**Go!** 🚀

---

**Last Updated**: 2025-10-19
**Status**: Ready for immediate installation
**Estimated Time**: 25 minutes
