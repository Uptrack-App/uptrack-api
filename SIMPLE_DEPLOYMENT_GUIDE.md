# Simple Deployment Guide - Idle Prevention on Oracle Always Free

**Status**: Code verified, works locally, need simple deployment method
**Goal**: Get idle prevention running on indiastrong and india-week without complex NixOS rebuilds

---

## Current Situation

✅ **Code Status**:
- Compiles locally WITHOUT ERRORS
- All idle prevention components working
- Deployed to ~/uptrack on indiastrong

❌ **Deployment Issue**:
- Complex NixOS rebuild failed
- Remote compilation hitting environment issues
- Need simpler approach

---

## Recommended Approach: Build Locally, Deploy Remotely

Instead of trying to compile on the remote system, build a **release on your local machine** and copy it:

### Step 1: Build Release Locally

```bash
cd /Users/le/repos/uptrack
MIX_ENV=prod mix release --overwrite
```

This creates: `_build/prod/rel/uptrack/`

### Step 2: Copy to Remote System

```bash
# Create directory on remote
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 "mkdir -p ~/uptrack_release"

# Copy release
rsync -av _build/prod/rel/uptrack/ le@152.67.179.42:~/uptrack_release/
```

### Step 3: Deploy Release

On the remote system:

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 << 'EOF'
# Create uptrack user if needed
sudo useradd -m -s /sbin/nologin uptrack 2>/dev/null || true

# Deploy
sudo rm -rf /opt/uptrack
sudo cp -r ~/uptrack_release /opt/uptrack
sudo chown -R uptrack:uptrack /opt/uptrack

# Create .env file
sudo tee /opt/uptrack/.env > /dev/null << 'DOTENV'
MIX_ENV=prod
PORT=4000
PHX_HOST=localhost
SECRET_KEY_BASE=your-secret-key-base-here
DATABASE_URL=postgresql://...
DOTENV

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable uptrack.service
sudo systemctl start uptrack.service

# Verify
sleep 2
sudo systemctl status uptrack
curl http://localhost:4000/api/health | jq '.checks.idle_prevention'
EOF
```

### Step 4: Verify Idle Prevention

```bash
# Check logs
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 \
  "sudo tail -50 /opt/uptrack/log/erlang.log | grep -i idle"

# Check health endpoint
curl http://152.67.179.42:4000/api/health | jq '.checks.idle_prevention'

# Should see stats like:
# {
#   "cpu_work_ms": 2450,
#   "memory_allocated_mb": 100,
#   "network_activity": "ok",
#   "disk_io": {"written": 1024000}
# }
```

---

## Why This Approach Works

| Aspect | Complex NixOS | Simple Release |
|--------|---------------|----------------|
| **Build Reliability** | ⚠️ Failed once | ✅ Works locally |
| **Complexity** | 🔴 Very High | 🟢 Simple |
| **Debug Difficulty** | 🔴 Hard | 🟢 Easy |
| **Deployment Time** | 🟡 15+ min | 🟢 < 5 min |
| **Rollback Time** | 🟡 Slow | 🟢 < 1 min |
| **Risk** | 🔴 HIGH | 🟢 LOW |

---

## Alternative: Run Without Service (Testing)

If you want to test quickly without systemd:

```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 << 'EOF'
cd ~/uptrack_release
export PORT=4000
export MIX_ENV=prod
./bin/uptrack start

# In another terminal:
curl http://localhost:4000/api/health
EOF
```

---

## Environment Variables Needed

The release needs these environment variables configured:

```bash
MIX_ENV=prod                              # Production mode
PORT=4000                                 # Web port
PHX_HOST=152.67.179.42                    # Hostname
SECRET_KEY_BASE=<generate-random>         # Phoenix secret
DATABASE_URL=postgresql://user:pass@host  # Database
OBAN_NODE_NAME=uptrack@152.67.179.42      # Oban node name
```

Generate SECRET_KEY_BASE:
```bash
mix phx.gen.secret
```

---

## Deployment to india-week

Once indiastrong is working, deploy to india-week **identically**:

```bash
# Copy same release
rsync -av _build/prod/rel/uptrack/ \
  le@152.67.179.99:~/uptrack_release/

# SSH and deploy same way
ssh -i ~/.ssh/id_ed25519 le@152.67.179.99 "..."
```

---

## Troubleshooting

### Release won't start

```bash
# Check systemd logs
sudo journalctl -u uptrack -n 50

# Check application logs
tail -50 /opt/uptrack/log/erlang.log

# Check if port is in use
sudo netstat -tulpn | grep 4000
```

### Health endpoint returns error

```bash
# Verify service is running
sudo systemctl status uptrack

# Check if it's accepting connections
curl -v http://localhost:4000/api/health

# Check database connectivity
psql -d uptrack -h localhost -c "SELECT 1"
```

### Idle prevention not running

```bash
# Check logs for errors
tail -100 /opt/uptrack/log/erlang.log | grep -i idle

# Verify GenServer started
# (need to connect to running app via iex)

# Check if Oban is running
psql -d uptrack -h localhost -c "SELECT * FROM oban_jobs LIMIT 5"
```

---

## Next Steps

### Immediate

1. Build release locally: `MIX_ENV=prod mix release --overwrite`
2. Deploy to indiastrong using rsync + deploy steps
3. Verify idle prevention logs
4. Confirm health endpoint works

### Then

1. Deploy same release to india-week
2. Monitor both for 24 hours
3. Confirm resource utilization > 20%
4. Document final setup

---

## Why Not NixOS Rebuild?

The NixOS rebuild approach failed because:

1. **Complex flake configuration** with multiple service modules
2. **Architecture mismatch** (aarch64 ARM64) with some dependencies
3. **Service conflicts** or syntax errors in module
4. **Environment-specific issues** during system activation

**This simpler approach is better because**:
- No system-level dependencies
- Uses standard Elixir release tooling
- Can test locally first
- Easy to debug and rollback
- Works on any OS/architecture

---

## Production Notes

For production use:
- Build releases in CI/CD pipeline
- Sign and verify releases
- Use systemd socket activation
- Set up log rotation
- Configure monitoring/alerts
- Set resource limits in systemd service

But for now, focus on **getting it working** with this simple approach.

---

**Status**: Ready to deploy using release method
**Next**: Build release and deploy to indiastrong
