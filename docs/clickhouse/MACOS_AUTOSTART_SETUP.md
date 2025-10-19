# ClickHouse Auto-Start Setup on macOS

**Goal**: Auto-start ClickHouse when your Mac boots (available to all users)
**Date**: 2025-10-19
**Approach**: LaunchDaemon (system-wide, all users)

---

## Step 1: Verify ClickHouse Installation

```bash
# Find where clickhouse is installed
which clickhouse

# Should return something like:
# /Users/le/.local/bin/clickhouse

# Test that it works
/Users/le/.local/bin/clickhouse --version
```

Note your installation path (we'll use it in the setup script).

---

## Step 2: Run the Setup Script

We provide an automated setup script that creates and installs the LaunchDaemon for you:

```bash
bash /Users/le/setup-clickhouse-launchd.sh
```

This script will:
- Create the LaunchDaemon plist
- Copy it to `/Library/LaunchDaemons/` (requires sudo)
- Set proper permissions
- Load the daemon
- Validate everything is working

**What is LaunchDaemon?**

A LaunchDaemon is a system-wide service that:
- Runs as root (accessible to all users)
- Auto-starts on system boot
- Restarts automatically if it crashes
- Is available to any user connecting to localhost:8123

---

## Step 3: Verify Installation

After running the setup script, verify ClickHouse is running:

```bash
# Check daemon status
launchctl list | grep com.uptrack.clickhouse

# Test connectivity
curl http://localhost:8123/ping

# Should return: Ok.
```

---

## Step 4: Test Auto-Start (Restart Your Mac)

To verify that ClickHouse auto-starts on boot:

```bash
# Restart your Mac
sudo shutdown -r +1

# After restart, verify it's running
curl http://localhost:8123/ping
# Should return: Ok.

# Check logs to confirm it started
tail -20 /var/log/clickhouse.log
```

---

## Control Commands

### Start/Stop ClickHouse

```bash
# Start manually
sudo launchctl start com.uptrack.clickhouse

# Stop
sudo launchctl stop com.uptrack.clickhouse

# Restart
sudo launchctl stop com.uptrack.clickhouse && sleep 1 && sudo launchctl start com.uptrack.clickhouse

# Check if running
launchctl list | grep com.uptrack.clickhouse
```

### Manage LaunchDaemon

```bash
# Unload (disable auto-start, but keep it)
sudo launchctl unload /Library/LaunchDaemons/com.uptrack.clickhouse.plist

# Load (enable auto-start again)
sudo launchctl load /Library/LaunchDaemons/com.uptrack.clickhouse.plist

# Remove completely
sudo launchctl unload /Library/LaunchDaemons/com.uptrack.clickhouse.plist
sudo rm /Library/LaunchDaemons/com.uptrack.clickhouse.plist
```

---

## Troubleshooting

### ClickHouse Not Starting

```bash
# Check plist syntax
plutil -lint /Library/LaunchDaemons/com.uptrack.clickhouse.plist

# Output should be: OK

# If not OK, check the file content
cat /Library/LaunchDaemons/com.uptrack.clickhouse.plist
```

### Check Logs

```bash
# Main log
tail -50 /var/log/clickhouse.log

# Error log
tail -50 /var/log/clickhouse.error.log

# System logs
log stream --predicate 'process == "launchd"' --level debug
```

### Port Already in Use

```bash
# Check what's using port 8123
lsof -i :8123

# Kill the process
kill -9 <PID>

# Restart ClickHouse
sudo launchctl stop com.uptrack.clickhouse && sleep 1 && sudo launchctl start com.uptrack.clickhouse
```

### Wrong ClickHouse Path

If you installed ClickHouse to a different location:

```bash
# Find correct path
which clickhouse

# Edit the LaunchDaemon plist
sudo nano /Library/LaunchDaemons/com.uptrack.clickhouse.plist

# Update the <string> value in ProgramArguments to your actual path
# Look for this section and update the path:
# <key>ProgramArguments</key>
# <array>
#     <string>/YOUR/ACTUAL/PATH/clickhouse</string>
#     <string>server</string>
# </array>

# Save and reload
sudo launchctl unload /Library/LaunchDaemons/com.uptrack.clickhouse.plist
sudo launchctl load /Library/LaunchDaemons/com.uptrack.clickhouse.plist
```

---

## Verify Setup

```bash
# 1. Check LaunchDaemon is loaded
launchctl list | grep com.uptrack.clickhouse

# 2. Check ClickHouse is running
curl http://localhost:8123/ping

# 3. Check logs
tail -20 /var/log/clickhouse.log

# 4. Test from Elixir
# iex -S mix
# alias Ch
# Ch.query(:default, "SELECT 1")
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `bash /Users/le/setup-clickhouse-launchd.sh` | Install LaunchDaemon (first time) |
| `sudo launchctl start com.uptrack.clickhouse` | Start manually |
| `sudo launchctl stop com.uptrack.clickhouse` | Stop |
| `launchctl list \| grep com.uptrack.clickhouse` | Check status |
| `curl http://localhost:8123/ping` | Test connection |
| `tail -20 /var/log/clickhouse.log` | View logs |
| `sudo launchctl unload /Library/LaunchDaemons/com.uptrack.clickhouse.plist` | Disable auto-start |
| `sudo launchctl load /Library/LaunchDaemons/com.uptrack.clickhouse.plist` | Re-enable auto-start |

---

## Environment Variables for Your App

Create `.env`:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default
```

Or use in `config/runtime.exs`:

```elixir
config :uptrack, :clickhouse,
  host: System.get_env("CLICKHOUSE_HOST", "localhost"),
  port: String.to_integer(System.get_env("CLICKHOUSE_PORT", "8123")),
  user: System.get_env("CLICKHOUSE_USER", "default"),
  password: System.get_env("CLICKHOUSE_PASSWORD", "default")
```

---

## Summary

✅ **Done!** Your setup:

1. ✅ LaunchDaemon plist installed at `/Library/LaunchDaemons/com.uptrack.clickhouse.plist`
2. ✅ Runs as system service (accessible to all users)
3. ✅ Auto-starts on Mac boot
4. ✅ Auto-restarts if ClickHouse crashes
5. ✅ Logs to `/var/log/clickhouse.log`
6. ✅ Available on `http://localhost:8123` for any user
7. ✅ Control with `sudo launchctl` commands

**Key Differences from LaunchAgent:**
- **LaunchAgent** = user context only (user must be logged in)
- **LaunchDaemon** = system context (runs all the time, available to all users)

**Next**: Start your app and use ResilientWriter to send data to ClickHouse!
