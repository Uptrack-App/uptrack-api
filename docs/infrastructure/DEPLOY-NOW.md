# Deploy Tailscale NOW - Step by Step

## Current Status
- ✅ Tailscale account created
- ✅ Auth key generated: `REMOVED_TAILSCALE_AUTH_KEY`
- ✅ NixOS configuration ready
- ⏳ Ready to deploy

## Deploy to Nodes

### Deploy to india-rworker (Oracle Cloud, REMOVED_IP)

```bash
cat scripts/install-tailscale-debian.sh | ssh root@REMOVED_IP 'bash -s india-rworker REMOVED_TAILSCALE_AUTH_KEY'
```

### Deploy to EU Nodes (Hostkey Italy)

```bash
# eu-a
cat scripts/install-tailscale-debian.sh | ssh root@REMOVED_IP 'bash -s eu-a REMOVED_TAILSCALE_AUTH_KEY'

# eu-b
cat scripts/install-tailscale-debian.sh | ssh root@REMOVED_IP 'bash -s eu-b REMOVED_TAILSCALE_AUTH_KEY'

# eu-c
cat scripts/install-tailscale-debian.sh | ssh root@REMOVED_IP 'bash -s eu-c REMOVED_TAILSCALE_AUTH_KEY'
```

### Assign Static IPs

1. Go to https://login.tailscale.com/admin/machines
2. For each machine, assign static IP:
   - india-rworker: `100.64.1.11`
   - eu-a: `100.64.1.1`
   - eu-b: `100.64.1.2`
   - eu-c: `100.64.1.3`

---

## What If It Fails?

### Tailscale doesn't connect

```bash
# Check if tailscaled is running
sudo systemctl status tailscaled

# Check logs
sudo journalctl -u tailscaled -n 50

# Restart if needed
sudo systemctl restart tailscaled
```

### Auth key expired

If you see "auth key expired", generate a new one:

1. Go to https://login.tailscale.com/admin/settings/keys
2. Generate new reusable, ephemeral key with tag:infrastructure
3. Update the TAILSCALE_AUTHKEY variable
4. Re-run deployment

---

## Quick Status Check

After deployment, verify everything:

```bash
# On india-rworker
ssh root@REMOVED_IP

# Check Tailscale
sudo tailscale status
sudo tailscale ip -4

# Check system
systemctl is-active tailscaled
```

Expected to see Tailscale connected and correct IP assigned.
