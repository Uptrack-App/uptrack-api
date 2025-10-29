# Manual NixOS Installation - Next Steps

## Status

✅ Scripts prepared and copied to instance
✅ Installation script ready on instance at `/tmp/install-nixos-live.sh`
✅ Download script ready on instance at `/tmp/download-and-install.sh`

---

## What You Need to Do Now

### Step 1: SSH to Instance and Run Download Script

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171

# Run the download and boot script
bash /tmp/download-and-install.sh
```

**What this does:**
- Downloads NixOS 25.05 ARM64 image (5-10 min)
- Decompresses it
- Asks you to confirm writing to /dev/sda
- Writes image using `dd` (3-5 min)
- Reboots into NixOS live environment

**Timeline:** ~15-20 minutes

---

### Step 2: Wait for NixOS Live Boot

The instance will reboot. Wait 3-5 minutes for NixOS live environment to boot.

Then SSH back in as root:

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
```

---

### Step 3: Run Installation Script

Once in NixOS live environment:

```bash
# Run the installation script
bash /tmp/install-nixos-live.sh
```

**What this does:**
1. Asks which disk to use (usually `/dev/sda`)
2. Creates partitions (EFI + root)
3. Formats filesystems
4. Generates NixOS configuration
5. Installs NixOS (10-20 min)
6. Reboots into installed NixOS

**Timeline:** ~40 minutes

---

### Step 4: After NixOS Reboots

Once NixOS is installed and boots, SSH in:

```bash
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171

# Verify NixOS
uname -a
nixos-rebuild --version
```

---

### Step 5: Deploy Uptrack Services

Clone repo and deploy:

```bash
cd /root
git clone https://github.com/your-repo/uptrack.git
cd uptrack

# Deploy services
sudo nixos-rebuild switch --flake .#node-india-strong
```

**Timeline:** ~10 minutes

---

## Complete Timeline

| Step | Time | Task |
|------|------|------|
| 1 | 15-20 min | Download image, write to disk, reboot |
| 2 | 3-5 min | NixOS live boot |
| 3 | 40 min | Partition, format, install |
| 4 | 5 min | Verify NixOS boot |
| 5 | 10 min | Deploy services |
| **Total** | **~75 min** | **Complete!** |

---

## Quick Reference Commands

```bash
# Step 1: Download and boot
ssh -i ~/.ssh/ssh-key-2025-10-18.key ubuntu@144.24.133.171
bash /tmp/download-and-install.sh

# Wait 5 minutes...

# Step 3: Install NixOS
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
bash /tmp/install-nixos-live.sh

# Wait for reboot (5-10 min)...

# Step 5: Deploy services
ssh -i ~/.ssh/ssh-key-2025-10-18.key root@144.24.133.171
cd /root/uptrack
nixos-rebuild switch --flake .#node-india-strong
```

---

## Important Notes

1. **Don't interrupt downloads** - Let them complete (slow connection to India)
2. **Installation takes time** - Wait 20 minutes without interrupting
3. **Reboots are normal** - System will reboot multiple times
4. **Watch for prompts** - The scripts ask for confirmation on disk writing
5. **SSH will disconnect** - During reboots, SSH connection will drop

---

## Troubleshooting

### Download Fails
- The scripts try multiple mirror URLs
- If all fail, the script will exit with error
- You can manually download from a working mirror

### Disk Write Fails
- Check `lsblk` to verify disk is `/dev/sda`
- Make sure you have 50GB free
- May need different device name

### Installation Hangs
- This is NORMAL - wait 20-30 minutes
- NixOS installation can be slow on slow connections
- Check with `top` in another SSH window if you're worried

### Services Not Starting
- Wait 5 minutes for services to boot
- Check logs: `sudo journalctl -u postgresql -n 50`
- Restart manually if needed: `sudo systemctl restart postgresql`

---

## Files Ready

✅ `/tmp/download-and-install.sh` - Download NixOS and boot live
✅ `/tmp/install-nixos-live.sh` - Install NixOS to disk
✅ `~/repos/uptrack/flake.nix` - Your Uptrack configuration

---

**You're ready! Start with Step 1 above.** 🚀

