# Systemd Service Files

Systemd units for managing Uptrack services on production nodes.

## Files

- `uptrack.service` - Main Phoenix application
- `clickhouse-spool-flush.service` - Flushes spooled ClickHouse writes
- `clickhouse-spool-flush.timer` - Runs flush service every minute
- `clickhouse-flush-spool.sh` - Shell script for flushing (called by service)

## Installation

### 1. Create uptrack User

```bash
# Create system user for running the app
useradd --system --create-home --shell /bin/bash uptrack

# Create directories
mkdir -p /opt/uptrack
mkdir -p /var/lib/uptrack/spool
mkdir -p /var/log/uptrack

# Set ownership
chown -R uptrack:uptrack /opt/uptrack
chown -R uptrack:uptrack /var/lib/uptrack
chown -R uptrack:uptrack /var/log/uptrack
```

### 2. Deploy Phoenix Service (All Nodes)

```bash
# Copy service file
cp uptrack.service /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Enable and start
systemctl enable uptrack
systemctl start uptrack

# Check status
systemctl status uptrack
journalctl -u uptrack -f
```

### 3. Deploy ClickHouse Flush (Node C Only)

```bash
# Copy files
cp clickhouse-spool-flush.service /etc/systemd/system/
cp clickhouse-spool-flush.timer /etc/systemd/system/
cp clickhouse-flush-spool.sh /usr/local/bin/
chmod +x /usr/local/bin/clickhouse-flush-spool.sh

# Reload systemd
systemctl daemon-reload

# Enable and start timer
systemctl enable clickhouse-spool-flush.timer
systemctl start clickhouse-spool-flush.timer

# Verify timer is active
systemctl list-timers --all | grep clickhouse

# Manual test
systemctl start clickhouse-spool-flush.service
journalctl -u clickhouse-spool-flush -f
```

## Environment Variables

Create `/opt/uptrack/.env` on each node:

```bash
# Database connections (via HAProxy to Patroni primary)
DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=app,public
OBAN_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=oban,public
RESULTS_DATABASE_URL=postgresql://uptrack:PASSWORD@127.0.0.1:6432/uptrack_prod?search_path=results,public

# Phoenix
SECRET_KEY_BASE=<run: mix phx.gen.secret>
PHX_HOST=uptrack.app
PHX_SERVER=true
PORT=4000
POOL_SIZE=10

# Oban node identification
OBAN_NODE_NAME=node-a  # Change per node: node-a, node-b, node-c
NODE_REGION=us-east    # Change per node: us-east, eu-central, ap-southeast

# ClickHouse (all nodes need this for writes)
CLICKHOUSE_HOST=100.C.C.C
CLICKHOUSE_PORT=8123
CLICKHOUSE_DATABASE=default

# OAuth
GITHUB_CLIENT_ID=your_github_client_id
GITHUB_CLIENT_SECRET=your_github_client_secret
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# Optional: Sentry, logging, etc.
# SENTRY_DSN=https://...
```

Set proper permissions:
```bash
chown uptrack:uptrack /opt/uptrack/.env
chmod 600 /opt/uptrack/.env
```

## Service Management

### Start/Stop/Restart

```bash
# Start
systemctl start uptrack

# Stop
systemctl stop uptrack

# Restart
systemctl restart uptrack

# Graceful reload (if app supports SIGUSR1)
systemctl reload uptrack
```

### View Logs

```bash
# Follow logs in real-time
journalctl -u uptrack -f

# Show last 100 lines
journalctl -u uptrack -n 100

# Show logs since boot
journalctl -u uptrack -b

# Show logs for last hour
journalctl -u uptrack --since "1 hour ago"

# Filter by log level
journalctl -u uptrack -p err  # errors only
```

### Check Status

```bash
# Service status
systemctl status uptrack

# Is service active?
systemctl is-active uptrack

# Is service enabled (start on boot)?
systemctl is-enabled uptrack
```

## Deployment Workflow

### Deploy New Release

```bash
# 1. Build release locally or in CI
MIX_ENV=prod mix release

# 2. Copy to server
scp _build/prod/rel/uptrack/uptrack-*.tar.gz node-a:/tmp/

# 3. Extract on server (as uptrack user)
ssh node-a
sudo su - uptrack
cd /opt/uptrack
tar -xzf /tmp/uptrack-*.tar.gz

# 4. Run migrations (only on one node)
/opt/uptrack/bin/uptrack eval "Uptrack.Release.migrate()"

# 5. Restart service
sudo systemctl restart uptrack

# 6. Verify
systemctl status uptrack
curl http://127.0.0.1:4000/healthz

# 7. Repeat for other nodes
```

### Rolling Deploy (Zero Downtime)

```bash
# Deploy to nodes one at a time
# Cloudflare will route traffic to healthy nodes

# Node A
ssh node-a "systemctl stop uptrack"
# Deploy new release
ssh node-a "systemctl start uptrack"
# Wait for health check: curl uptrack.app/healthz

# Node B
ssh node-b "systemctl stop uptrack"
# Deploy new release
ssh node-b "systemctl start uptrack"
# Wait for health check

# Node C
ssh node-c "systemctl stop uptrack"
# Deploy new release
ssh node-c "systemctl start uptrack"
# Wait for health check
```

## Troubleshooting

### Service won't start

```bash
# Check logs
journalctl -u uptrack -n 50

# Common issues:
# 1. Permission denied
ls -la /opt/uptrack
chown -R uptrack:uptrack /opt/uptrack

# 2. Database connection failed
psql -h 127.0.0.1 -p 6432 -U uptrack -d uptrack_prod

# 3. Port already in use
netstat -tuln | grep 4000
# Kill conflicting process or change PORT in .env

# 4. Missing .env file
ls -la /opt/uptrack/.env
```

### Service crashes repeatedly

```bash
# Check crash logs
journalctl -u uptrack -p err

# Check resource usage
top -u uptrack
free -h
df -h

# Increase restart delay (edit uptrack.service)
RestartSec=30s
systemctl daemon-reload
systemctl restart uptrack
```

### ClickHouse spool keeps growing

```bash
# Check if ClickHouse is reachable
echo "SELECT 1" | clickhouse-client --host=100.C.C.C

# Check spool flush logs
journalctl -u clickhouse-spool-flush -f

# Manual flush
systemctl start clickhouse-spool-flush.service

# If ClickHouse is down, spool will accumulate (this is expected)
# Once ClickHouse is back, flush will catch up
```

## Monitoring

### Key Metrics to Track

```bash
# Service uptime
systemctl show uptrack --property=ActiveEnterTimestamp

# Memory usage
systemctl status uptrack | grep Memory

# CPU usage
systemctl status uptrack | grep CPU

# Restart count (should be low)
systemctl show uptrack --property=NRestarts
```

### Alerting

Set up alerts for:
- Service status: `systemctl is-active uptrack`
- Restart count exceeds threshold
- Memory usage > 80%
- Disk usage > 80%

Example with systemd-notify:

```bash
# Send email when service fails
OnFailure=email-alert@%n.service
```

## Log Rotation

Journald handles log rotation automatically, but you can configure limits:

```bash
# Edit /etc/systemd/journald.conf
SystemMaxUse=1G
SystemMaxFileSize=100M
MaxRetentionSec=7day

# Restart journald
systemctl restart systemd-journald
```

## Security

### Service Hardening (Optional)

Add to `[Service]` section in `uptrack.service`:

```ini
# Restrict filesystem access
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/uptrack /var/lib/uptrack /var/log/uptrack

# Restrict network
PrivateNetwork=false  # Must be false for app to work
RestrictAddressFamilies=AF_INET AF_INET6

# Restrict capabilities
CapabilityBoundingSet=
AmbientCapabilities=
NoNewPrivileges=true

# Restrict syscalls
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
```

Test after adding hardening:
```bash
systemctl daemon-reload
systemctl restart uptrack
systemctl status uptrack
```

## Performance Tuning

### Adjust File Descriptor Limit

For high-traffic apps:

```ini
# In uptrack.service [Service] section
LimitNOFILE=1048576
```

### Adjust OOM Killer Score

Protect critical services:

```ini
# Lower score = less likely to be killed
OOMScoreAdjust=-100
```

### Enable Core Dumps (for debugging crashes)

```ini
LimitCORE=infinity
```

Core dumps saved to `/var/lib/systemd/coredump/`

## Upgrade Systemd Units

```bash
# After editing service files
systemctl daemon-reload

# Restart affected services
systemctl restart uptrack
systemctl restart clickhouse-spool-flush.timer
```

## Uninstall

```bash
# Stop and disable services
systemctl stop uptrack clickhouse-spool-flush.timer
systemctl disable uptrack clickhouse-spool-flush.timer

# Remove service files
rm /etc/systemd/system/uptrack.service
rm /etc/systemd/system/clickhouse-spool-flush.{service,timer}
rm /usr/local/bin/clickhouse-flush-spool.sh

# Reload systemd
systemctl daemon-reload

# Remove user and data (careful!)
userdel -r uptrack
rm -rf /opt/uptrack
rm -rf /var/lib/uptrack
rm -rf /var/log/uptrack
```
