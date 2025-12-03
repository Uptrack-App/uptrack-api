# Deploy Tailscale NOW - Step by Step

## Current Status
- ✅ Tailscale account created
- ✅ Auth key generated: `REMOVED_TAILSCALE_AUTH_KEY`
- ✅ NixOS configuration ready
- ⏳ Ready to deploy

## Deploy to india-s (152.67.179.42)

### Option A: Automated Script (Recommended)

From your local machine:

```bash
cd /Users/le/repos/uptrack
./scripts/deploy-tailscale-india-s.sh
```

**Duration:** 15-20 minutes (first build)

### Option B: Manual Step-by-Step

If the script fails, follow these manual steps:

#### Step 1: SSH to the node

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
```

#### Step 2: Navigate to repo (or clone if needed)

```bash
# If repo exists:
cd ~/repos/uptrack
git pull origin main

# If repo doesn't exist:
mkdir -p ~/repos
cd ~/repos
git clone https://github.com/yourusername/uptrack.git
cd uptrack
```

#### Step 3: Validate configuration

```bash
sudo nixos-rebuild dry-build --flake '.#india-hyderabad-1'
```

**Expected:** "building the system configuration..." (no errors)

#### Step 4: Build configuration

```bash
sudo nixos-rebuild build --flake '.#india-hyderabad-1' --max-jobs 3
```

**Duration:** 15-20 minutes first time, 5-10 minutes subsequent builds

**Expected output:**
```
building the system configuration...
building '/nix/store/...'
these derivations will be built:
  /nix/store/...tailscale...
...
[lots of build output]
...
building the system configuration...
/nix/store/xxxxx-nixos-system-uptrack-india-hyderabad-1-24.11
```

#### Step 5: Set auth key and switch

```bash
export TAILSCALE_AUTHKEY="REMOVED_TAILSCALE_AUTH_KEY"

sudo -E nixos-rebuild switch --flake '.#india-hyderabad-1'
```

**Expected output:**
```
activating the configuration...
setting up /etc...
reloading the following units: dbus.service
restarting the following units: polkit.service
starting the following units: tailscale-autoconnect.service, tailscaled.service
...
Tailscale connected successfully
Tailscale IP: 100.64.x.x
```

#### Step 6: Verify Tailscale

```bash
sudo tailscale status
```

**Expected:**
```
100.64.x.x   india-s   hoangbytes@gmail.com   linux   active; relay "xxx"
```

```bash
sudo tailscale ip -4
```

**Expected:**
```
100.64.1.XXX
```

### Step 7: Assign Static IP

1. Go to https://login.tailscale.com/admin/machines
2. Find machine named **"india-s"**
3. Click the machine
4. Click ⚙️ (settings icon)
5. Click **"Edit IP address"**
6. Enter: `100.64.1.10`
7. Click **"Save"**

### Step 8: Verify Static IP

On the node:

```bash
sudo tailscale ip -4
```

**Expected:**
```
100.64.1.10
```

---

## What If It Fails?

### Build fails with "permission denied"

```bash
# Check if you have sudo access
sudo echo "test"

# If fails, you need root or sudo privileges
```

### Tailscale doesn't connect

```bash
# Check if tailscaled is running
sudo systemctl status tailscaled

# Check logs
sudo journalctl -u tailscaled -n 50

# Restart if needed
sudo systemctl restart tailscaled
sudo systemctl restart tailscale-autoconnect
```

### Auth key expired

If you see "auth key expired", generate a new one:

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate new reusable, ephemeral key with tag:infrastructure
3. Update the TAILSCALE_AUTHKEY variable
4. Re-run step 5

### Build takes too long

The first build compiles PostgreSQL 17 and other packages. This is normal.

To monitor progress:
```bash
# In another SSH session, watch system resources
htop

# Check what's being built
ps aux | grep nix-daemon
```

---

## After india-s is Complete

Next nodes to deploy:

1. **india-w** (Oracle Cloud, India Mumbai)
   - Get IP from Oracle console
   - Run: `./scripts/install-tailscale-debian.sh` with hostname `india-w`

2. **EU nodes** (Hostkey Italy)
   - Get IPs from Hostkey dashboard
   - Run: `./scripts/install-tailscale-debian.sh` for each:
     - `eu-a`
     - `eu-b`
     - `eu-c`

3. **Assign all static IPs** in Tailscale admin console

4. **Verify connectivity** between all nodes

---

## Troubleshooting SSH

If you can't SSH to india-s:

```bash
# Check if SSH key exists
ls -la ~/.ssh/id_ed25519

# Check SSH config
cat ~/.ssh/config

# Test connection with verbose output
ssh -v -i ~/.ssh/id_ed25519 le@152.67.179.42
```

If using different key:
```bash
ssh -i ~/.ssh/your-actual-key le@152.67.179.42
```

---

## Quick Status Check

After deployment, verify everything:

```bash
# On india-s
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Check Tailscale
sudo tailscale status
sudo tailscale ip -4

# Check system
systemctl is-active tailscaled
systemctl is-active postgresql

# Check NixOS generation
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Expected to see new generation with Tailscale module loaded.
