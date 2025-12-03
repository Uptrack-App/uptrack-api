# Implementation Tasks

## Phase 1: Pre-deployment Verification (15 minutes)

### Verify Prerequisites
- [x] Tailscale account created (hoangbytes@gmail.com)
- [x] Auth key generated (tskey-auth-kpxV7eU19h11CNTRL-rvHLb1SbQd1xaS8gPgJQd17fk2Fmgnzg, expires Jan 28, 2026)
- [x] Tag `infrastructure` created in Tailscale admin
- [x] Node inventory documented with all IPs
- [x] NixOS Tailscale module created (`infra/nixos/modules/services/tailscale.nix`)
- [x] Debian installation script created (`scripts/install-tailscale-debian.sh`)
- [x] Deployment script created (`scripts/deploy-tailscale-all.sh`)

### Test SSH Access
- [ ] Test SSH to india-s: `ssh -i ~/.ssh/id_ed25519 le@152.67.179.42`
- [ ] Test SSH to india-w: `ssh root@144.24.150.48`
- [ ] Test SSH to eu-a: `ssh root@194.180.207.223`
- [ ] Test SSH to eu-b: `ssh root@194.180.207.225`
- [ ] Test SSH to eu-c: `ssh root@194.180.207.226`

## Phase 2: Tailscale Deployment (45 minutes)

### Deploy to india-s (NixOS)
- [ ] Sync code to remote node: `rsync` or `git pull`
- [ ] Run dry-build: `sudo nixos-rebuild dry-build --flake '.#india-hyderabad-1'`
- [ ] Build configuration: `sudo nixos-rebuild build --flake '.#india-hyderabad-1' --max-jobs 3`
- [ ] Switch with auth key: `sudo TAILSCALE_AUTHKEY="..." nixos-rebuild switch --flake '.#india-hyderabad-1'`
- [ ] Verify Tailscale status: `sudo tailscale status`
- [ ] Verify Tailscale IP: `sudo tailscale ip -4`
- [ ] Check service status: `systemctl is-active tailscaled`

### Deploy to india-w
- [ ] Run installation script: `cat scripts/install-tailscale-debian.sh | ssh root@144.24.150.48 'bash -s india-w tskey-auth-...'`
- [ ] Verify node appears in Tailscale admin console
- [ ] Verify Tailscale IP: `ssh root@144.24.150.48 'sudo tailscale ip -4'`
- [ ] Test ping from india-s to india-w (should be <10ms)

### Deploy to eu-a
- [ ] Run installation script: `cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.223 'bash -s eu-a tskey-auth-...'`
- [ ] Verify node appears in Tailscale admin console
- [ ] Verify Tailscale IP: `ssh root@194.180.207.223 'sudo tailscale ip -4'`

### Deploy to eu-b
- [ ] Run installation script: `cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.225 'bash -s eu-b tskey-auth-...'`
- [ ] Verify node appears in Tailscale admin console
- [ ] Verify Tailscale IP: `ssh root@194.180.207.225 'sudo tailscale ip -4'`

### Deploy to eu-c
- [ ] Run installation script: `cat scripts/install-tailscale-debian.sh | ssh root@194.180.207.226 'bash -s eu-c tskey-auth-...'`
- [ ] Verify node appears in Tailscale admin console
- [ ] Verify Tailscale IP: `ssh root@194.180.207.226 'sudo tailscale ip -4'`

## Phase 3: Static IP Assignment (10 minutes)

### Assign Static IPs via Admin Console
- [ ] Go to https://login.tailscale.com/admin/machines
- [ ] Verify all 5 machines are online: india-s, india-w, eu-a, eu-b, eu-c
- [ ] Assign static IP to india-s: 100.64.1.10
  - Click machine → ⚙️ → Edit IP address → Enter `100.64.1.10` → Save
- [ ] Assign static IP to india-w: 100.64.1.11
- [ ] Assign static IP to eu-a: 100.64.1.1
- [ ] Assign static IP to eu-b: 100.64.1.2
- [ ] Assign static IP to eu-c: 100.64.1.3
- [ ] Wait 10 seconds for changes to propagate

### Verify Static IPs
- [ ] Verify india-s: `ssh le@152.67.179.42 'sudo tailscale ip -4'` shows `100.64.1.10`
- [ ] Verify india-w: `ssh root@144.24.150.48 'sudo tailscale ip -4'` shows `100.64.1.11`
- [ ] Verify eu-a: `ssh root@194.180.207.223 'sudo tailscale ip -4'` shows `100.64.1.1`
- [ ] Verify eu-b: `ssh root@194.180.207.225 'sudo tailscale ip -4'` shows `100.64.1.2`
- [ ] Verify eu-c: `ssh root@194.180.207.226 'sudo tailscale ip -4'` shows `100.64.1.3`

## Phase 4: Connectivity Verification (20 minutes)

### Ping Tests - EU Internal
- [ ] From eu-a, ping eu-b: `ssh root@194.180.207.223 'ping -c 3 100.64.1.2'` (expect <20ms)
- [ ] From eu-a, ping eu-c: `ssh root@194.180.207.223 'ping -c 3 100.64.1.3'` (expect <20ms)
- [ ] From eu-b, ping eu-c: `ssh root@194.180.207.225 'ping -c 3 100.64.1.3'` (expect <20ms)

### Ping Tests - India Internal
- [ ] From india-s, ping india-w: `ssh le@152.67.179.42 'ping -c 3 100.64.1.11'` (expect <10ms)

### Ping Tests - Cross-Region
- [ ] From india-s, ping eu-a: `ssh le@152.67.179.42 'ping -c 3 100.64.1.1'` (expect ~150ms)
- [ ] From india-s, ping eu-b: `ssh le@152.67.179.42 'ping -c 3 100.64.1.2'` (expect ~150ms)
- [ ] From india-s, ping eu-c: `ssh le@152.67.179.42 'ping -c 3 100.64.1.3'` (expect ~150ms)
- [ ] From eu-a, ping india-s: `ssh root@194.180.207.223 'ping -c 3 100.64.1.10'` (expect ~150ms)
- [ ] From eu-a, ping india-w: `ssh root@194.180.207.223 'ping -c 3 100.64.1.11'` (expect ~150ms)

### SSH Tests via Tailscale IPs
- [ ] From local machine, SSH to india-s: `ssh le@100.64.1.10` (via Tailscale)
- [ ] From local machine, SSH to india-w: `ssh root@100.64.1.11`
- [ ] From local machine, SSH to eu-a: `ssh root@100.64.1.1`
- [ ] From local machine, SSH to eu-b: `ssh root@100.64.1.2`
- [ ] From local machine, SSH to eu-c: `ssh root@100.64.1.3`
- [ ] From india-s, SSH to eu-a: `ssh -i ~/.ssh/id_ed25519 le@152.67.179.42` then `ssh root@100.64.1.1`

### Full Connectivity Matrix
- [ ] Document all 20 ping results (5 nodes × 4 other nodes each)
- [ ] Verify 0% packet loss for all tests
- [ ] Verify latency expectations met (EU <20ms, cross-region ~150ms)

## Phase 5: Auto-Start Verification (10 minutes)

### Test Auto-Reconnect
- [ ] Reboot india-s: `ssh le@152.67.179.42 'sudo reboot'`
- [ ] Wait 60 seconds for boot
- [ ] Verify india-s appears online in Tailscale admin
- [ ] Verify india-s Tailscale IP still 100.64.1.10
- [ ] Ping india-s from another node to confirm connectivity

### Verify systemd Services
- [ ] Check tailscaled service: `systemctl is-active tailscaled` (should be "active")
- [ ] Check tailscaled enabled: `systemctl is-enabled tailscaled` (should be "enabled")
- [ ] Check service logs: `journalctl -u tailscaled -n 20` (should show successful connection)

## Phase 6: Documentation (10 minutes)

### Update Node Inventory
- [ ] Update `docs/infrastructure/node-inventory.md` with Tailscale IPs
- [ ] Add connectivity matrix results to documentation
- [ ] Document last verified date
- [ ] Add example SSH commands using Tailscale IPs

### Create Quick Reference
- [ ] Document static IP mapping in quick reference guide
- [ ] Add troubleshooting section with common issues
- [ ] Document rollback procedure if needed

## Phase 7: Validation (5 minutes)

### Final Checklist
- [ ] All 5 nodes visible in Tailscale admin console with status "Online"
- [ ] All nodes have correct static IPs assigned
- [ ] All nodes tagged with `tag:infrastructure`
- [ ] Ping works between all node pairs (20/20 tests pass)
- [ ] SSH works via Tailscale IPs from any node
- [ ] Latency meets expectations (EU <20ms, cross-region ~150ms)
- [ ] Auto-start verified (at least one node rebooted and reconnected)
- [ ] Documentation updated with all Tailscale IPs
- [ ] Auth key expiration documented (Jan 28, 2026)

### Success Criteria Met
- [ ] Can SSH to any node via Tailscale IP: `ssh user@100.64.1.X`
- [ ] Services can reference nodes by static Tailscale IPs in configs
- [ ] Network ready for Phase 2 (etcd cluster deployment)

## Rollback Procedure (If Needed)

If Tailscale causes issues:

### Remove Tailscale from NixOS Node
- [ ] SSH to node: `ssh -i ~/.ssh/id_ed25519 le@152.67.179.42`
- [ ] Rollback: `sudo nixos-rebuild switch --rollback`
- [ ] Verify SSH still works via public IP

### Remove Tailscale from Debian Nodes
- [ ] SSH to node: `ssh root@<public-ip>`
- [ ] Stop service: `sudo systemctl stop tailscaled`
- [ ] Disable service: `sudo systemctl disable tailscaled`
- [ ] Remove package: `sudo apt remove tailscale`
- [ ] Verify SSH still works via public IP

### Clean Up Tailscale Admin
- [ ] Go to https://login.tailscale.com/admin/machines
- [ ] Delete removed machines
- [ ] Revoke auth key if compromised: Settings → Keys → Delete key
