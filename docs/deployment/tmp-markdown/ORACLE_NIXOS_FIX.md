# Oracle + nixos-anywhere: Ubuntu User Requirement

## The Issue

When running `nixos-anywhere` on an Oracle Cloud Ubuntu instance, you get:

```
ERROR: Please login as the user "ubuntu" rather than the user "root".
```

---

## Why This Happens

Oracle Cloud Ubuntu instances come with:
- ✅ `ubuntu` user (sudoer, can escalate to root)
- ❌ `root` user (disabled by default, no direct SSH access)

Security best practice: Direct root SSH access is disabled.

---

## The Solution

**Connect as `ubuntu` (not `root`) for initial setup:**

### ✅ CORRECT:
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  -i ~/.ssh/ssh-key-2025-10-18.key \
  ubuntu@144.24.133.171
        ^^^^^^
        Connect as ubuntu
```

### ❌ WRONG:
```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#node-india-strong \
  -i ~/.ssh/ssh-key-2025-10-18.key \
  root@144.24.133.171
  ^^^^
  This will fail!
```

---

## What nixos-anywhere Does

When you connect as `ubuntu`:

1. **SSH connects** as `ubuntu` user ✅
2. **Escalates** to root using `sudo` (ubuntu is a sudoer) ✅
3. **Installs NixOS** with full permissions ✅
4. **Reboots** system with new NixOS ✅
5. **After reboot**, you can SSH as `root` directly ✅

---

## After NixOS Installation

Once NixOS is installed, you CAN login as `root`:

```bash
# After installation - root login works!
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
```

This is fine - NixOS enables root SSH access by default.

---

## Files Fixed

- ✅ `install-nixos-india-strong.sh` - Updated to use ubuntu@
- ✅ `NIXOS_INSTALLATION.md` - Updated command examples

---

## Summary

| Stage | User | Why |
|-------|------|-----|
| **Before NixOS** | ubuntu | Oracle requires this |
| **nixos-anywhere** | ubuntu | Uses sudo to escalate |
| **After NixOS** | root | NixOS enables it |

---

## Related

- Oracle Cloud documentation: Ubuntu images with disabled root SSH
- nixos-anywhere documentation: Supports connecting as non-root user
- NixOS security practices: Disabling root SSH is secure

