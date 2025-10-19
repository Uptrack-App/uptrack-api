# ClickHouse Docker Export & Setup

**Purpose**: Export your local ClickHouse to Docker for production/sharing
**Date**: 2025-10-19

---

## Local Setup (macOS)

### Quick Setup - Auto-Start on Boot

**File created**: `~/Library/LaunchAgents/com.uptrack.clickhouse.plist`

**To enable auto-start:**

```bash
# Load the LaunchAgent (run this once)
launchctl load ~/Library/LaunchAgents/com.uptrack.clickhouse.plist

# Verify it's running
curl http://localhost:8123/ping
# Should return: Ok.

# Check logs
tail -f /var/log/clickhouse-server.log
```

**Control commands:**

```bash
# Start manually
launchctl start com.uptrack.clickhouse

# Stop
launchctl stop com.uptrack.clickhouse

# Restart
launchctl restart com.uptrack.clickhouse

# Check status
launchctl list com.uptrack.clickhouse

# Disable auto-start
launchctl unload ~/Library/LaunchAgents/com.uptrack.clickhouse.plist
```

**Test auto-start after restart:**

```bash
# Restart Mac, then verify
curl http://localhost:8123/ping
tail /var/log/clickhouse-server.log
```

---

## Docker Setup (Production/Sharing)

### Option 1: Use docker-compose.dev.yml (Recommended)

```bash
# Start ClickHouse in Docker
docker-compose -f docker-compose.dev.yml up -d

# Verify it's running
curl http://localhost:8123/ping

# Stop when done
docker-compose -f docker-compose.dev.yml down
```

**docker-compose.dev.yml already created** with:
- ClickHouse service
- Port 8123 (HTTP) and 9000 (Native)
- Data persistence via volumes
- Health checks

---

### Option 2: Standalone Docker Container

```bash
# Start ClickHouse container
docker run -d \
  --name uptrack-clickhouse \
  -p 8123:8123 \
  -p 9000:9000 \
  -v clickhouse-data:/var/lib/clickhouse \
  clickhouse/clickhouse-server:latest

# Verify it's running
curl http://localhost:8123/ping

# View logs
docker logs -f uptrack-clickhouse

# Stop
docker stop uptrack-clickhouse

# Start again later
docker start uptrack-clickhouse

# Remove container (deletes everything)
docker rm uptrack-clickhouse
```

---

### Option 3: Custom Docker Image with Your Config

```dockerfile
# Dockerfile
FROM clickhouse/clickhouse-server:latest

# Copy your config
COPY clickhouse-config.xml /etc/clickhouse-server/config.d/custom.xml

# Copy any data initialization scripts
COPY init-db.sh /docker-entrypoint-initdb.d/

EXPOSE 8123 9000
```

Build and run:

```bash
docker build -t uptrack-clickhouse .
docker run -d -p 8123:8123 -p 9000:9000 uptrack-clickhouse
```

---

## Comparison: Local vs Docker

| Aspect | Local (macOS) | Docker |
|--------|---------------|--------|
| **Setup** | LaunchAgent plist | docker-compose up |
| **Auto-start** | ✅ Via launchctl | Via docker daemon |
| **Data persistence** | File system | Docker volume |
| **Isolation** | None (system) | ✅ Isolated |
| **Sharing** | ❌ Machine-specific | ✅ Works anywhere |
| **Production-ready** | ⚠️ Not recommended | ✅ Yes |
| **Performance** | ✅ Native | Slight overhead |

**Recommendation**:
- **Local dev**: Use macOS LaunchAgent (native, fast)
- **Production/CI**: Use Docker (reproducible, isolated)
- **Team sharing**: Use docker-compose.dev.yml

---

## Export Data from Local to Docker

### Backup local data

```bash
# Export your ClickHouse database
clickhouse-client --query "SELECT * FROM checks_raw" > checks_raw_backup.tsv

# Or backup the entire data directory
tar -czf ~/.clickhouse-local/data backup-clickhouse-data.tar.gz
```

### Restore into Docker

```bash
# Start Docker container
docker-compose -f docker-compose.dev.yml up -d

# Restore data
docker exec uptrack-clickhouse clickhouse-client < checks_raw_backup.tsv

# Or restore directory
docker cp backup-clickhouse-data.tar.gz uptrack-clickhouse:/backup.tar.gz
docker exec uptrack-clickhouse tar -xzf /backup.tar.gz -C /var/lib/clickhouse
```

---

## Quick Reference

### Local macOS Setup

```bash
# One-time setup
launchctl load ~/Library/LaunchAgents/com.uptrack.clickhouse.plist

# After restart, verify
curl http://localhost:8123/ping

# Control
launchctl restart com.uptrack.clickhouse
```

### Docker Setup

```bash
# Start
docker-compose -f docker-compose.dev.yml up -d

# Stop
docker-compose -f docker-compose.dev.yml down

# Logs
docker-compose -f docker-compose.dev.yml logs -f clickhouse
```

---

## Environment Variables

Both local and Docker versions use:

```bash
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default
```

Set in `.env`:

```bash
# .env
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default
```

Or in `config/runtime.exs`:

```elixir
clickhouse_host = System.get_env("CLICKHOUSE_HOST", "localhost")
clickhouse_port = String.to_integer(System.get_env("CLICKHOUSE_PORT", "8123"))
```

---

## Troubleshooting

### Local (macOS)

```bash
# Check if running
launchctl list com.uptrack.clickhouse

# View logs
tail -50 /var/log/clickhouse-server.log

# Restart
launchctl restart com.uptrack.clickhouse

# Port in use?
lsof -i :8123
```

### Docker

```bash
# Check if running
docker ps | grep clickhouse

# View logs
docker-compose -f docker-compose.dev.yml logs clickhouse

# Restart
docker-compose -f docker-compose.dev.yml restart

# Port in use?
lsof -i :8123
```

---

## Next Steps

1. **Set up LaunchAgent** (already done)
   ```bash
   launchctl load ~/Library/LaunchAgents/com.uptrack.clickhouse.plist
   ```

2. **Create ClickHouse tables** (see resilient_writer.md)
   ```sql
   CREATE TABLE checks_raw (...)
   ```

3. **Implement ResilientWriter** in your app

4. **Test end-to-end**
   ```bash
   curl "http://localhost:8123/?query=SELECT%20*%20FROM%20checks_raw"
   ```

5. **For production**: Use Docker

---

## Summary

- ✅ **Local dev**: LaunchAgent (auto-starts on boot)
- ✅ **Docker**: docker-compose up (for production/sharing)
- ✅ **Both**: Same connection (localhost:8123)
- ✅ **Backup**: Export/restore data between them
