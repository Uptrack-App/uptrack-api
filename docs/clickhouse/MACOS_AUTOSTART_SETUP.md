# ClickHouse Auto-Start Setup on macOS

**Goal**: Auto-start ClickHouse when your Mac boots
**Date**: 2025-10-19
**Approach**: LaunchAgent (standard macOS method)

---

## Step 1: Find ClickHouse Installation Location

```bash
# Find where clickhouse-server is installed
which clickhouse-server
which clickhouse

# Should return something like:
# /Users/le/.local/bin/clickhouse-server
# or
# /usr/local/bin/clickhouse-server
```

Note your path (we'll use it in step 2).

---

## Step 2: Create LaunchAgent Plist File

Create the file: `~/Library/LaunchAgents/com.uptrack.ch.plist`

```bash
mkdir -p ~/Library/LaunchAgents

cat > ~/Library/LaunchAgents/com.uptrack.ch.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.uptrack.ch</string>

    <key>Program</key>
    <string>/Users/le/.local/bin/clickhouse-server</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <true/>
    </dict>

    <key>StandardOutPath</key>
    <string>/var/log/clickhouse.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/clickhouse.error.log</string>

    <key>WorkingDirectory</key>
    <string>/Users/le</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

# Verify file was created
cat ~/Library/LaunchAgents/com.uptrack.ch.plist
```

---

## Step 3: Load the LaunchAgent

```bash
# Load the agent
launchctl load ~/Library/LaunchAgents/com.uptrack.ch.plist

# Check if it loaded successfully
launchctl list | grep com.uptrack.ch

# Output should show something like:
# "com.uptrack.ch"
```

---

## Step 4: Verify ClickHouse is Running

```bash
# Check if it's responding
curl http://localhost:8123/ping

# Should return: Ok.

# Check logs
tail -20 /var/log/clickhouse.log

# Check process
ps aux | grep clickhouse
```

---

## Step 5: Test Auto-Start (Restart Your Mac)

```bash
# Restart your Mac
sudo shutdown -r +1

# After restart, verify it's running
curl http://localhost:8123/ping
# Should return: Ok.

# Check logs to confirm it started
tail /var/log/clickhouse.log
```

---

## Control Commands

### Start/Stop ClickHouse

```bash
# Start manually
launchctl start com.uptrack.ch

# Stop
launchctl stop com.uptrack.ch

# Restart
launchctl stop com.uptrack.ch && sleep 1 && launchctl start com.uptrack.ch

# Check if running
launchctl list com.uptrack.ch

# View last exit code (0 = success)
# launchctl list com.uptrack.ch | awk '{print $1}'
```

### Manage LaunchAgent

```bash
# Unload (disable auto-start, but keep it)
launchctl unload ~/Library/LaunchAgents/com.uptrack.ch.plist

# Load (enable auto-start again)
launchctl load ~/Library/LaunchAgents/com.uptrack.ch.plist

# Remove completely
launchctl unload ~/Library/LaunchAgents/com.uptrack.ch.plist
rm ~/Library/LaunchAgents/com.uptrack.ch.plist
```

---

## Troubleshooting

### ClickHouse Not Starting

```bash
# Check plist syntax
plutil -lint ~/Library/LaunchAgents/com.uptrack.ch.plist

# Output should be: OK

# If not OK, check the file content
cat ~/Library/LaunchAgents/com.uptrack.ch.plist
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
launchctl stop com.uptrack.ch && sleep 1 && launchctl start com.uptrack.ch
```

### Wrong ClickHouse Path

If ClickHouse path is different:

```bash
# Find correct path
which clickhouse-server

# Edit plist file
nano ~/Library/LaunchAgents/com.uptrack.ch.plist

# Change the <string>/Users/le/.local/bin/clickhouse-server</string> line
# to your actual path

# Save and reload
launchctl unload ~/Library/LaunchAgents/com.uptrack.ch.plist
launchctl load ~/Library/LaunchAgents/com.uptrack.ch.plist
```

---

## Verify Setup

```bash
# 1. Check LaunchAgent is loaded
launchctl list | grep com.uptrack.ch

# 2. Check ClickHouse is running
curl http://localhost:8123/ping

# 3. Check logs
tail /var/log/clickhouse.log

# 4. Test from Elixir
# iex -S mix
# alias Ch
# Ch.query(:default, "SELECT 1")
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `launchctl load ~/Library/LaunchAgents/com.uptrack.ch.plist` | Enable auto-start |
| `launchctl unload ~/Library/LaunchAgents/com.uptrack.ch.plist` | Disable auto-start |
| `launchctl start com.uptrack.ch` | Start manually |
| `launchctl stop com.uptrack.ch` | Stop |
| `launchctl list com.uptrack.ch` | Check status |
| `curl http://localhost:8123/ping` | Test connection |
| `tail /var/log/clickhouse.log` | View logs |

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

1. ✅ LaunchAgent plist created at `~/Library/LaunchAgents/com.uptrack.ch.plist`
2. ✅ Auto-starts on Mac boot
3. ✅ Logs to `/var/log/clickhouse.log`
4. ✅ Can control with `launchctl` commands
5. ✅ Test with `curl http://localhost:8123/ping`

**Next**: Start your app and use ResilientWriter to send data to ClickHouse!
