# ClickHouse Local Development Setup

**Purpose**: Running ClickHouse locally during development
**Date**: 2025-10-19

---

## Quick Start: Using Docker (Recommended for Dev)

### Option 1: Docker (Easiest)

```bash
# Start ClickHouse in Docker
docker run -d \
  --name clickhouse-local \
  -p 8123:8123 \
  -p 9000:9000 \
  -v clickhouse-data:/var/lib/clickhouse \
  clickhouse/clickhouse-server:latest

# Verify it's running
curl http://localhost:8123/ping

# Stop when done
docker stop clickhouse-local
docker start clickhouse-local  # Restart later
```

**Pros**:
- ✅ Isolated from system
- ✅ Easy to stop/start
- ✅ Data persists in Docker volume
- ✅ No manual management

**Cons**:
- Requires Docker

---

## Option 2: Standalone Binary (Advanced)

Using the script you created at `/scripts/install_clickhouse_lts.sh`:

### 1. Install ClickHouse Binary

```bash
# Make script executable
chmod +x scripts/install_clickhouse_lts.sh

# Install to ~/.local/bin (adds to PATH if needed)
scripts/install_clickhouse_lts.sh

# Verify installation
which clickhouse
clickhouse --version
```

### 2. Create Data Directory

```bash
# ClickHouse needs a data directory
mkdir -p ~/.clickhouse-local/data
mkdir -p ~/.clickhouse-local/logs
```

### 3. Start ClickHouse Server

```bash
# Start in foreground (for development, see output)
clickhouse-server --config-file ~/.clickhouse-local/config.xml

# OR start in background
nohup clickhouse-server > ~/.clickhouse-local/clickhouse.log 2>&1 &
```

### 4. Connect to ClickHouse

```bash
# In another terminal
clickhouse-client

# Or use curl (HTTP interface)
curl http://localhost:8123/ping

# Or from Elixir (via ch library)
```

### 5. Stop ClickHouse

```bash
# If running in foreground: Ctrl+C

# If running in background
pkill -f clickhouse-server
```

---

## Integration with Elixir Dev Environment

### Environment Variables

Create `.env` for local development:

```bash
# .env
CLICKHOUSE_HOST=localhost
CLICKHOUSE_PORT=8123
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=default
```

### Testing with ch Library

```elixir
# In iex or test
alias Ch

# Try a simple query
case Ch.query(:default, "SELECT 1") do
  {:ok, result} -> IO.inspect(result)
  {:error, reason} -> IO.inspect(reason)
end
```

---

## Recommended: Docker Compose (Best for Dev)

Create `docker-compose.dev.yml`:

```yaml
version: '3.8'

services:
  clickhouse:
    image: clickhouse/clickhouse-server:latest
    container_name: uptrack-clickhouse-dev
    ports:
      - "8123:8123"    # HTTP
      - "9000:9000"    # Native
    volumes:
      - clickhouse-data:/var/lib/clickhouse
      - clickhouse-logs:/var/log/clickhouse-server
    environment:
      - CLICKHOUSE_DB=default
      - CLICKHOUSE_USER=default
      - CLICKHOUSE_PASSWORD=default
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123/ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  clickhouse-data:
  clickhouse-logs:
```

Usage:

```bash
# Start
docker-compose -f docker-compose.dev.yml up -d

# Stop
docker-compose -f docker-compose.dev.yml down

# View logs
docker-compose -f docker-compose.dev.yml logs -f clickhouse

# Clean everything (delete data)
docker-compose -f docker-compose.dev.yml down -v
```

---

## Development Workflow

### 1. Start ClickHouse

```bash
# Option A: Docker
docker-compose -f docker-compose.dev.yml up -d

# Option B: Binary
clickhouse-server
```

### 2. Run Phoenix App

```bash
mix phx.server
```

### 3. App connects to ClickHouse automatically

```elixir
# In your code, assuming ch library is configured
Uptrack.ResilientWriter.write_check_result(%{
  monitor_id: "123",
  status: "up",
  response_time_ms: 145,
  region: "us-east"
})
```

### 4. Verify Data in ClickHouse

```bash
# Via clickhouse-client
clickhouse-client
> SELECT * FROM checks_raw LIMIT 5;

# Via HTTP
curl "http://localhost:8123/?query=SELECT%20*%20FROM%20checks_raw%20LIMIT%205"
```

### 5. Stop When Done

```bash
# Option A: Docker
docker-compose -f docker-compose.dev.yml down

# Option B: Binary
Ctrl+C or pkill clickhouse-server
```

---

## Troubleshooting

### ClickHouse Won't Start

```bash
# Check if port 8123/9000 already in use
lsof -i :8123
lsof -i :9000

# Kill conflicting process
kill -9 <PID>

# Try again
clickhouse-server
```

### Connection Refused

```bash
# Verify ClickHouse is running
curl http://localhost:8123/ping

# Should return: Ok.

# If not, check logs
tail -f ~/.clickhouse-local/clickhouse.log
```

### Data Not Appearing

```bash
# Check if table exists
clickhouse-client
> SHOW TABLES;

# Create table if needed
> CREATE TABLE checks_raw (
    monitor_id UUID,
    status String,
    response_time_ms UInt32,
    region String,
    checked_at DateTime
  ) ENGINE = MergeTree()
  ORDER BY checked_at;
```

---

## Recommended Setup for Development

**I recommend Docker Compose** because:

1. ✅ Isolated from system
2. ✅ Easy start/stop
3. ✅ No manual port conflicts
4. ✅ Works same as production (via Docker)
5. ✅ Persistent volume (data survives restart)
6. ✅ Easy cleanup (no leftover processes)

### Setup Steps

```bash
# 1. Create docker-compose.dev.yml (see above)
# 2. Start
docker-compose -f docker-compose.dev.yml up -d

# 3. Start your app
mix phx.server

# 4. Test ResilientWriter
# (your app sends data to ClickHouse)

# 5. View data
curl "http://localhost:8123/?query=SELECT%20*%20FROM%20checks_raw"

# 6. Stop when done
docker-compose -f docker-compose.dev.yml down
```

---

## Next: Schema Setup

After ClickHouse is running, you need to:

1. Create the `checks_raw` table
2. Ensure ResilientWriter can insert data
3. Test end-to-end

See `/docs/clickhouse/resilient_writer.md` for schema and implementation.

---

**TL;DR for Local Dev:**

```bash
# Start (pick one)
docker-compose -f docker-compose.dev.yml up -d    # Docker (recommended)
# OR
clickhouse-server                                   # Binary

# Stop
docker-compose -f docker-compose.dev.yml down
# OR
Ctrl+C
```
