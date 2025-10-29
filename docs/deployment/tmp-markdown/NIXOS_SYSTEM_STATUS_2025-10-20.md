# NixOS System Status - 2025-10-20

## ✅ Installation Status: SUCCESSFUL

Successfully installed and configured NixOS on Oracle Cloud ARM64 (aarch64) instance.

---

## System Information

| Property | Value |
|----------|-------|
| **Hostname** | indiastrong |
| **IP Address** | 152.67.179.42 |
| **OS** | NixOS 24.11 |
| **Architecture** | aarch64 (ARM64) |
| **Kernel** | 6.12.32-NixOS |
| **Nix Version** | 2.28.3 |
| **SSH User** | le |
| **SSH Key Type** | ed25519 |

---

## Hardware Resources

### Storage
- **Root Partition (/)**: 46GB total, 3.0GB used, 40GB available (7% usage)
- **Boot Partition (/boot)**: 511MB total, 82MB used, 430MB available (16% usage)

### Memory
- **RAM**: 17GB total, 402MB used, 17GB free
- **Swap**: 0B (disabled)
- **Available**: 17GB free

### Disk Performance
- **Disk Device**: /dev/sda
- **Root Filesystem**: /dev/sda2
- **Boot Filesystem**: /dev/sda1 (EFI)

---

## Network Configuration

| Setting | Value |
|---------|-------|
| **Network Manager** | Enabled |
| **Firewall** | Enabled |
| **Allowed TCP Ports** | 22 (SSH) |
| **SSH Service** | Active & Running |
| **Root Login** | Disabled |
| **Password Auth** | Disabled (Key-only) |

---

## Active Services (13 running)

| Service | Status | Purpose |
|---------|--------|---------|
| sshd.service | ✅ Running | SSH Daemon |
| nix-daemon.service | ✅ Running | Nix Package Manager |
| NetworkManager.service | ✅ Running | Network Management |
| systemd-journald.service | ✅ Running | System Logging |
| systemd-timesyncd.service | ✅ Running | NTP Time Sync |
| systemd-logind.service | ✅ Running | User Login Management |
| dbus.service | ✅ Running | System Message Bus |
| nscd.service | ✅ Running | Name Service Cache |
| getty@tty1.service | ✅ Running | Console 1 |
| serial-getty@ttyAMA0.service | ✅ Running | Serial Console |
| systemd-oomd.service | ✅ Running | OOM Killer |
| systemd-udevd.service | ✅ Running | Device Management |
| user@1000.service | ✅ Running | User Session (le) |

---

## System Packages

Basic utilities pre-installed:
- curl
- git
- vim
- wget

---

## Configuration Files Structure

Located in `/etc/nixos/`:

```
configuration.nix          # Main system configuration
hardware-configuration.nix # Hardware-specific settings
disk-config.nix           # Disk partitioning configuration
vars.nix                  # Configuration variables
```

### Key Configuration Details

**vars.nix**:
```nix
{
  hostname = "indiastrong";
  username = "le";
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com";
  locale = "en_US.UTF-8";
  timezone = "Asia/Kolkata";
}
```

**Security Settings**:
- SSH Key-based authentication only
- Root login disabled
- Passwordless sudo enabled for user `le`
- User `le` in `wheel` and `networkmanager` groups
- Immutable users (no password changes via system)

**Boot Configuration**:
- Bootloader: systemd-boot
- EFI boot enabled
- Can touch EFI variables: true
- Systemd in initrd enabled

---

## SSH Connection

### From Local Machine

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
```

### Verified Access ✅

Successfully connected and verified:
- SSH connectivity: Working
- User permissions: Correct
- Key authentication: Functional
- System responsiveness: Excellent

---

## Timezone & Locale

| Setting | Value |
|---------|-------|
| **Timezone** | Asia/Kolkata (IST UTC+5:30) |
| **Locale** | en_US.UTF-8 |

---

## Next Steps

The NixOS system is fully operational and ready for:

1. **Application Deployment**
   - Deploy services using Nix flakes
   - Use `nixos-rebuild switch` for config changes
   - Manage packages via `nix-env` or flakes

2. **System Management**
   - Monitor with `systemctl` commands
   - Update with `nix flake update && nixos-rebuild switch`
   - Review logs with `journalctl`

3. **Development**
   - Use Nix development shells (`nix develop`)
   - Build and test applications declaratively
   - Create reproducible development environments

4. **Monitoring**
   - Set up system monitoring (e.g., Prometheus, Grafana)
   - Configure log aggregation
   - Set up alerting for critical services

---

## Additional Notes

- **System is minimal**: Documentation disabled for minimal install size
- **Reproducible**: Full declarative configuration enables easy recovery/replication
- **Immutable**: NixOS ensures system consistency across rebuilds
- **Disk space**: Abundant storage available for applications and data
- **Memory**: Sufficient resources for production workloads

---

**Last Updated**: 2025-10-20
**Status**: ✅ Production Ready
