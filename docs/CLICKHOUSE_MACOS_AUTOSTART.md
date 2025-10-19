# ClickHouse Auto-Start on macOS

**Goal**: ClickHouse starts automatically when your Mac boots
**Date**: 2025-10-19

---

## Method 1: LaunchAgent (Recommended)

A LaunchAgent runs in user context (no sudo needed) and starts on login.

### 1. Create LaunchAgent Plist

```bash
# Create the directory if it doesn't exist
mkdir -p ~/Library/LaunchAgents

# Create the plist file
cat > ~/Library/LaunchAgents/com.clickhouse.server.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clickhouse.server</string>

    <key>Program</key>
    <string>/Users/YOUR_USERNAME/.local/bin/clickhouse-server</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/var/log/clickhouse-server.log</string>

    <key>StandardErrorPath</key>
    <string>/var/log/clickhouse-server.error.log</string>

    <key>UserName</key>
    <string>YOUR_USERNAME</string>
</dict>
</plist>
EOF
```

**IMPORTANT**: Replace `YOUR_USERNAME` with your actual macOS username!

To find your username:
```bash
whoami
```

### 2. Load the LaunchAgent

```bash
# Load the agent
launchctl load ~/Library/LaunchAgents/com.clickhouse.server.plist

# Verify it's loaded
launchctl list | grep clickhouse
```

### 3. Test It

```bash
# Check if ClickHouse is running
curl http://localhost:8123/ping

# Should return: Ok.

# Check logs
tail -f /var/log/clickhouse-server.log
```

### 4. Control Commands

```bash
# Start manually
launchctl start com.clickhouse.server

# Stop
launchctl stop com.clickhouse.server

# Restart
launchctl stop com.clickhouse.server && launchctl start com.clickhouse.server

# Unload (disable auto-start)
launchctl unload ~/Library/LaunchAgents/com.clickhouse.server.plist

# Check status
launchctl list com.clickhouse.server
```

---

## Method 2: Using Homebrew (If You Install via Brew)

If you want to use Homebrew for ClickHouse:

```bash
# Install via Homebrew
brew install clickhouse

# Start the service
brew services start clickhouse

# Auto-start is now enabled!

# Check status
brew services list

# Stop
brew services stop clickhouse
```

---

## Troubleshooting

### LaunchAgent Not Starting

```bash
# Check if plist is valid
plutil -lint ~/Library/LaunchAgents/com.clickhouse.server.plist

# Check launchd logs
log stream --predicate 'process == "launchd"' --level debug
```

### Port Already in Use

```bash
# Check what's using port 8123
lsof -i :8123

# Kill it
kill -9 <PID>

# Restart ClickHouse
launchctl restart com.clickhouse.server
```

### Permissions Issues

```bash
# Fix plist permissions
chmod 644 ~/Library/LaunchAgents/com.clickhouse.server.plist

# Reload
launchctl unload ~/Library/LaunchAgents/com.clickhouse.server.plist
launchctl load ~/Library/LaunchAgents/com.clickhouse.server.plist
```

### ClickHouse Not Responding

```bash
# Check logs
tail -50 /var/log/clickhouse-server.log

# Verify it's running
ps aux | grep clickhouse

# Restart
launchctl restart com.clickhouse.server
```

---

## Verify Auto-Start Works

After setting up LaunchAgent:

1. **Restart your Mac**
   ```bash
   # Schedule restart
   sudo shutdown -r +1
   ```

2. **After restart, check if it's running**
   ```bash
   curl http://localhost:8123/ping
   # Should return: Ok.
   ```

3. **Check logs**
   ```bash
   tail /var/log/clickhouse-server.log
   ```

---

## Configuration File

If you need custom ClickHouse config, edit:

```bash
# Default config location
~/.clickhouse-local/config.xml

# Or wherever you configured it
```

Then restart:
```bash
launchctl restart com.clickhouse.server
```

---

## Summary

**Quick Setup:**

```bash
# 1. Find your username
whoami

# 2. Replace YOUR_USERNAME in this command and run:
cat > ~/Library/LaunchAgents/com.clickhouse.server.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clickhouse.server</string>
    <key>Program</key>
    <string>/Users/YOUR_USERNAME/.local/bin/clickhouse-server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/clickhouse-server.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/clickhouse-server.error.log</string>
    <key>UserName</key>
    <string>YOUR_USERNAME</string>
</dict>
</plist>
EOF

# 3. Load it
launchctl load ~/Library/LaunchAgents/com.clickhouse.server.plist

# 4. Verify
curl http://localhost:8123/ping

# 5. Restart Mac to test auto-start
```

Done! ✅ ClickHouse will now start automatically when you log in.
