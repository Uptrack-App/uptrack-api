# SSH Key Permissions Guide

## The Problem

When connecting via SSH with an improperly permissioned key, you get:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for '/Users/le/.ssh/ssh-key-2025-10-18.key' are too open.
It is required that your private key files are NOT accessible by others.
This private key will be ignored.
Load key "/Users/le/.ssh/ssh-key-2025-10-18.key": bad permissions
ubuntu@144.24.133.171: Permission denied (publickey).
```

---

## Why This Matters

SSH is **very strict about private key permissions** for security reasons:

1. **Private keys are secrets** - they unlock your servers
2. **If permissions are too open**, anyone on the machine can read your key
3. **SSH refuses to use it** - even if you own the file
4. **Default file creation** often creates 644 permissions (readable by all)

---

## Understanding File Permissions

### Permission Notation

```
-rw-r--r--
│││││││││
││││││││└─ Other: Execute
│││││││└── Other: Write
││││││└─── Other: Read
│││││└──── Group: Execute
││││└───── Group: Write
│││└────── Group: Read
││└─────── Owner: Execute
│└──────── Owner: Write
└───────── Owner: Read (and file type)
```

### Octal Notation

Each group (owner, group, other) is represented as:
- **4** = Read (r)
- **2** = Write (w)
- **1** = Execute (x)
- **0** = No permission

**Common Examples:**

| Octal | Symbolic | Meaning |
|-------|----------|---------|
| **600** | `-rw-------` | Owner can read/write, no one else |
| **644** | `-rw-r--r--` | Owner can read/write, others can read |
| **755** | `-rwxr-xr-x` | Owner full access, others read/execute |
| **700** | `-rwx------` | Owner full access, no one else |

---

## SSH Key Permission Requirements

### Private Key File

**Required Permission: 600** (`-rw-------`)

```
chmod 600 ~/.ssh/private_key
```

**Why:**
- Owner (you) can read and write
- No one else can read (not even group or others)
- SSH will refuse to use it if less restrictive

### Public Key File

**Recommended Permission: 644** (`-rw-r--r--`)

```
chmod 644 ~/.ssh/public_key.pub
```

**Why:**
- Owner can read and write
- Others can read (they need to copy this to servers)
- Can't modify (no write for group/others)

### SSH Directory

**Recommended Permission: 700** (`drwx------`)

```
chmod 700 ~/.ssh
```

**Why:**
- Only you can access the directory
- Others can't read your keys
- Standard practice for security

---

## Fix SSH Key Permissions

### Step 1: Check Current Permissions

```bash
ls -la ~/.ssh/ssh-key-2025-10-18.key
```

**Current (problematic):**
```
-rw-r--r--@ 1 le  staff   1675 Oct 19 17:59 ssh-key-2025-10-18.key
                                              └─ 644 permissions (too open!)
```

**Expected:**
```
-rw-------@ 1 le  staff   1675 Oct 19 17:59 ssh-key-2025-10-18.key
                                             └─ 600 permissions (correct!)
```

### Step 2: Fix the Permissions

```bash
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

### Step 3: Verify Fix

```bash
ls -la ~/.ssh/ssh-key-2025-10-18.key
```

Should show: `-rw-------` (600 permissions)

---

## Complete SSH Directory Setup

### Secure Your Entire SSH Directory

```bash
# Fix SSH directory permissions
chmod 700 ~/.ssh

# Fix all private key permissions
chmod 600 ~/.ssh/id_*
chmod 600 ~/.ssh/*_key
chmod 600 ~/.ssh/ssh-key-*

# Fix public key permissions (if needed)
chmod 644 ~/.ssh/*.pub

# Verify
ls -la ~/.ssh/
```

**Expected Output:**
```
drwx------   le  staff   ~/.ssh/
-rw-------   le  staff   id_ed25519
-rw-r--r--   le  staff   id_ed25519.pub
-rw-------   le  staff   ssh-key-2025-10-18.key
-rw-r--r--   le  staff   ssh-key-2025-10-18.key.pub
```

---

## Troubleshooting

### Issue 1: "Permission denied (publickey)"

**Check:**
```bash
# Is the key file readable?
ls -la ~/.ssh/ssh-key-2025-10-18.key

# Should show: -rw------- (600)
```

**Fix:**
```bash
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

### Issue 2: "UNPROTECTED PRIVATE KEY FILE"

**This means:** Permissions are 644 or less restrictive than 600

**Fix:**
```bash
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

### Issue 3: SSH Still Refuses the Key After chmod

**Check for extended attributes (macOS specific):**
```bash
ls -la@ ~/.ssh/ssh-key-2025-10-18.key
```

If you see extra attributes like `@`, try:
```bash
# Remove extended attributes
xattr -c ~/.ssh/ssh-key-2025-10-18.key

# Then fix permissions again
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

### Issue 4: "No such file or directory"

**Make sure you're using the correct path:**
```bash
# Don't use ~ if not in your home directory
chmod 600 /Users/le/.ssh/ssh-key-2025-10-18.key

# Or use ~ (expands to your home)
chmod 600 ~/.ssh/ssh-key-2025-10-18.key
```

---

## Automated Setup Script

Create a script to fix all SSH permissions at once:

```bash
#!/bin/bash
# Fix SSH directory and key permissions

echo "Fixing SSH directory and key permissions..."

# Fix SSH directory
chmod 700 ~/.ssh
echo "✓ SSH directory: 700"

# Fix private keys
for key in ~/.ssh/id_* ~/.ssh/*_key ~/.ssh/ssh-key-*; do
    if [ -f "$key" ] && [ ! -f "$key.pub" ]; then
        chmod 600 "$key"
        echo "✓ Fixed: $key"
    fi
done

# Fix public keys
for pub in ~/.ssh/*.pub; do
    if [ -f "$pub" ]; then
        chmod 644 "$pub"
        echo "✓ Fixed: $pub"
    fi
done

echo ""
echo "SSH permissions fixed!"
ls -la ~/.ssh/
```

Save as `~/.local/bin/fix-ssh-perms.sh` and run:
```bash
chmod +x ~/.local/bin/fix-ssh-perms.sh
~/.local/bin/fix-ssh-perms.sh
```

---

## SSH Connection After Permission Fix

### Test the Connection

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

**Expected:**
- No more "UNPROTECTED PRIVATE KEY FILE" warning
- Should connect successfully or ask for password
- Should NOT show "Permission denied (publickey)"

### With Verbose Output

If still having issues, debug with verbose output:

```bash
ssh -vv -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
```

This will show exactly what SSH is checking and why it might be failing.

---

## Security Best Practices

1. ✅ **Keep private keys to 600** - Only readable by owner
2. ✅ **Keep SSH directory to 700** - Only accessible by owner
3. ✅ **Use strong key passphrases** - If you use passphrases
4. ✅ **Don't share private keys** - Ever
5. ✅ **Regularly rotate keys** - Especially for production
6. ✅ **Use ssh-agent** - Avoid typing passphrases repeatedly

### SSH Agent Setup (macOS)

Add your key to SSH agent to avoid retyping passphrase:

```bash
# Add key to agent
ssh-add -K ~/.ssh/ssh-key-2025-10-18.key

# List keys in agent
ssh-add -l
```

---

## Common SSH Permission Scenarios

### Scenario 1: NixOS Installation

**Required:** 600 permissions on SSH key

```bash
chmod 600 ~/.ssh/ssh-key-2025-10-18.key

# Then run nixos-anywhere
nix run github:nix-community/nixos-anywhere -- \
  --flake .#india-rworker \
  -i ~/.ssh/ssh-key-2025-10-18.key \
  root@144.24.133.171
```

### Scenario 2: Git over SSH

**Required:** 600 permissions on key

```bash
chmod 600 ~/.ssh/id_ed25519
ssh-add -K ~/.ssh/id_ed25519
git clone git@github.com:user/repo.git
```

### Scenario 3: Multiple Keys

**Fix all at once:**

```bash
chmod 600 ~/.ssh/id_*
chmod 600 ~/.ssh/*_key
chmod 600 ~/.ssh/ssh-key-*
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Fix private key | `chmod 600 ~/.ssh/ssh-key-2025-10-18.key` |
| Fix SSH directory | `chmod 700 ~/.ssh` |
| Check permissions | `ls -la ~/.ssh/` |
| Fix all keys | `chmod 600 ~/.ssh/id_* ~/.ssh/*_key ~/.ssh/ssh-key-*` |
| Remove ext attrs (macOS) | `xattr -c ~/.ssh/ssh-key-2025-10-18.key` |
| Add to SSH agent | `ssh-add -K ~/.ssh/ssh-key-2025-10-18.key` |
| Test SSH | `ssh -vv -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171` |

---

## Related Documentation

- [SSH Manual Page](https://linux.die.net/man/1/ssh)
- [SSH Key Generation](https://linux.die.net/man/1/ssh-keygen)
- [SSH Config File](https://linux.die.net/man/5/ssh_config)
- [SSH Agent](https://linux.die.net/man/1/ssh-agent)

---

**Last Updated**: 2025-10-19
**Status**: Reference for SSH key permission issues
