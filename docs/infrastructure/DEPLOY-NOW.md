# Deploy Tailscale NOW - Step by Step

## Current Status
- ✅ Tailscale account created
- ✅ Auth key generated: `tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg`
- ✅ NixOS configuration ready
- ⏳ Ready to deploy

## Deploy to Nodes

### Deploy to india-rworker (Oracle Cloud, 144.24.150.48)

```bash
cat scripts/install-tailscale-debian.sh | ssh root@144.24.150.48 'bash -s india-rworker tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
```

### Deploy to EU Nodes (Hostkey Italy)

```bash
# eu-a
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.223 'bash -s eu-a tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'

# eu-b
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.225 'bash -s eu-b tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'

# eu-c
cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.226 'bash -s eu-c tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg'
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
ssh root@144.24.150.48

# Check Tailscale
sudo tailscale status
sudo tailscale ip -4

# Check system
systemctl is-active tailscaled
```

Expected to see Tailscale connected and correct IP assigned.
