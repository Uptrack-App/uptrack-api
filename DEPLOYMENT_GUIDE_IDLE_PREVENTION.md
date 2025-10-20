# Deployment Guide: Idle Prevention System

This guide covers deploying the Idle Prevention System to Oracle Always Free instances (indiastrong and india-week).

---

## Quick Start

### Prerequisites
- SSH access to target instance
- Git repository with idle prevention code
- Running Uptrack application
- Oban database migrations in place

### Deployment Time
- **Estimated**: 10-15 minutes
- **Downtime**: 0-1 minute (application restart)

---

## Step-by-Step Deployment

### Step 1: Pull Latest Code

**On local machine:**
```bash
cd /Users/le/repos/uptrack
git pull origin main
```

**Verify commit is present:**
```bash
git log --oneline | head -5
# Should show: "Add idle prevention system for Oracle Always Free instances"
```

### Step 2: Build Application

**Locally (optional verification):**
```bash
mix deps.get
mix compile
```

### Step 3: Deploy to indiastrong

#### Option A: Using nixos-rebuild (Recommended for NixOS)

**1. Push code to repository:**
```bash
git push origin main
```

**2. SSH into indiastrong:**
```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
```

**3. Pull latest code:**
```bash
cd /path/to/uptrack
git pull origin main
```

**4. Rebuild system (if using NixOS flakes):**
```bash
cd /path/to/uptrack
nix flake update
nixos-rebuild switch --flake .#indiastrong
```

**5. Verify compilation:**
```bash
# Check for errors in output
# Look for: "warning: the following collisions were detected"
# This is normal and can be ignored
```

#### Option B: Direct Application Restart

**1. SSH into indiastrong:**
```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
```

**2. Navigate to application:**
```bash
cd /path/to/uptrack
```

**3. Pull latest code:**
```bash
git pull origin main
```

**4. Compile new code:**
```bash
MIX_ENV=prod mix compile
```

**5. Restart application:**
```bash
# If using systemd
sudo systemctl restart uptrack

# If using supervised process
# Kill the existing Erlang VM
killall beam.smp

# Or gracefully via Erlang RPC (if available)
```

### Step 4: Verify Deployment

**Check application is running:**
```bash
# SSH into indiastrong
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Check process
ps aux | grep beam

# Check logs for IdlePrevention startup
tail -50 /path/to/uptrack/logs/*.log | grep -i idle

# Should see:
# [IdlePrevention] Starting idle prevention monitor
```

**Test health endpoint:**
```bash
# From local machine
curl http://152.67.179.42:4000/api/health | jq .

# Expected response:
# {
#   "status": "healthy",
#   "checks": {
#     "database": "ok",
#     "oban": "ok",
#     "idle_prevention": {
#       "cpu_work_ms": 2450,
#       "memory_allocated_mb": 100,
#       "network_activity": "ok",
#       "disk_io": {"written": 1024000}
#     },
#     "node_region": "unknown",
#     "node_name": "uptrack@152.67.179.42"
#   },
#   "timestamp": "2025-10-20T12:34:56.789Z"
# }
```

**Wait for first cycle (5 minutes):**
```bash
# Check logs again after 5 minutes
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42 \
  "tail -20 /path/to/uptrack/logs/*.log | grep -i idle"

# Should show:
# [IdlePrevention] Cycle complete:
#   - CPU work: XXXXms
#   - Memory allocated: 100MB
#   - Network: :ok
#   - Disk I/O: ...
```

---

## Deployment to india-week

Follow the same steps as indiastrong, but replace:
```bash
ssh -i ~/.ssh/id_ed25519 le@<india-week-ip>
```

With actual india-week IP address.

---

## Post-Deployment Verification

### Immediate Checks (within 1 minute)

- [ ] Application is running: `ps aux | grep beam`
- [ ] No errors in logs: `tail -100 /path/to/uptrack/logs/*.log | grep -i error`
- [ ] Health endpoint responds: `curl http://localhost:4000/api/health`

### Short-term Checks (within 10 minutes)

- [ ] IdlePrevention GenServer started
- [ ] First 5-minute cycle completed
- [ ] Health endpoint includes idle_prevention stats
- [ ] No database errors in logs

### Long-term Checks (ongoing)

- [ ] Every 5 minutes: See cycle completion logs
- [ ] Every 3 hours: See IdlePreventionWorker execution
- [ ] Resource utilization increases as expected
- [ ] No increase in error rate
- [ ] Application performance unchanged

---

## Monitoring After Deployment

### Real-time Log Monitoring

```bash
# SSH into indiastrong
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Watch idle prevention logs
tail -f /path/to/uptrack/logs/*.log | grep -i idle

# Or watch all logs
tail -f /path/to/uptrack/logs/*.log
```

### Resource Monitoring

```bash
# Watch system resources during load generation
watch -n 1 'free -h; echo "---"; top -b -n1 | head -10'

# Monitor specific metrics
top -p $(pgrep -f beam) -b -n1

# Check disk usage
df -h

# Check network traffic
ifstat -i eth0 1 5
```

### Oban Job Monitoring

If you have access to Oban Web UI (at `/oban`):

1. Navigate to: `http://152.67.179.42:4000/oban`
2. Look for `Uptrack.Monitoring.IdlePreventionWorker`
3. Verify job completes every 3 hours
4. Check `completed` state for successful runs
5. Review execution times

### Database Monitoring

```bash
# SSH into instance with database access
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42

# Connect to PostgreSQL
psql -d uptrack -h localhost

# Check Oban jobs
SELECT id, worker, state, attempt, inserted_at, completed_at
FROM oban_jobs
WHERE worker = 'Uptrack.Monitoring.IdlePreventionWorker'
ORDER BY id DESC LIMIT 10;

# Check job completion rate
SELECT
  state,
  COUNT(*) as count,
  AVG(EXTRACT(EPOCH FROM (completed_at - inserted_at))) as avg_duration_sec
FROM oban_jobs
WHERE worker = 'Uptrack.Monitoring.IdlePreventionWorker'
GROUP BY state;
```

---

## Troubleshooting

### IdlePrevention Not Running

**Issue**: Logs don't show `[IdlePrevention] Starting idle prevention monitor`

**Diagnosis**:
```bash
# Check if GenServer is in supervision tree
iex> Supervisor.which_children(Uptrack.Supervisor)

# Look for: {Uptrack.Health.IdlePrevention, ...}
```

**Solutions**:
1. Verify code was deployed: `grep -r IdlePrevention /path/to/uptrack/lib`
2. Verify config change: `grep -n "IdlePrevention" /path/to/uptrack/lib/uptrack/application.ex`
3. Restart application: `systemctl restart uptrack`
4. Check compilation errors: `MIX_ENV=prod mix compile`

### Oban Job Not Running

**Issue**: No `IdlePreventionWorker` jobs in Oban queue

**Diagnosis**:
```bash
iex> Oban.check_repository(Uptrack.ObanRepo)
{:ok, "Repository is ready for Oban"}

# Check if Cron plugin is enabled
iex> Application.get_env(:uptrack, Oban)[:plugins]
```

**Solutions**:
1. Verify Oban Cron configuration: `grep -A5 "IdlePreventionWorker" /path/to/uptrack/config/config.exs`
2. Verify Oban is running: `iex> Oban.check_repository(Uptrack.ObanRepo)`
3. Force Oban restart: `iex> Oban.pause_queue(:default); Oban.resume_queue(:default)`
4. Check for parsing errors in crontab schedule

### High CPU/Memory Usage

**Issue**: Sustained high resource usage outside of load generation cycles

**Diagnosis**:
```bash
# Check if processes are finishing
top -p $(pgrep -f beam) -b -n1

# Monitor for specific tasks not completing
ps aux | grep erl

# Check for error loops in logs
tail -100 /path/to/uptrack/logs/*.log | grep -i error
```

**Solutions**:
1. Verify task timeouts in code
2. Check for infinite loops in computation
3. Monitor memory growth: `watch -n 2 'free -h'`
4. Temporarily disable: Comment out in config, restart

### Network Requests Failing

**Issue**: Logs show network activity failures

**Diagnosis**:
```bash
# Test local health endpoint
curl http://localhost:4000/api/health

# Check if endpoint is accessible
netstat -tuln | grep 4000

# Check port forwarding (if applicable)
sudo iptables -L -n | grep 4000
```

**Solutions**:
1. Verify health endpoint is working: `curl -v http://localhost:4000/api/health`
2. Check firewall rules
3. Verify application is bound to correct interface
4. Increase timeout in `idle_prevention.ex`

---

## Rollback Plan

If deployment causes issues:

### Immediate Rollback (< 1 minute)

**SSH into instance:**
```bash
ssh -i ~/.ssh/id_ed25519 le@152.67.179.42
```

**Revert to previous commit:**
```bash
cd /path/to/uptrack
git revert HEAD --no-edit
# or
git reset --hard HEAD~1
```

**Rebuild and restart:**
```bash
MIX_ENV=prod mix compile
systemctl restart uptrack
```

### Verify Rollback

```bash
# Check that IdlePrevention logs are gone
tail -100 /path/to/uptrack/logs/*.log | grep IdlePrevention
# Should show: (no results)

# Check health endpoint
curl http://localhost:4000/api/health | jq '.checks.idle_prevention'
# Should show error or not present
```

### If Rollback Fails

1. Stop the application: `systemctl stop uptrack`
2. Check disk space: `df -h`
3. Check database connectivity: `psql -d uptrack -h localhost -c "SELECT 1"`
4. Check error logs: `journalctl -u uptrack -n 50`
5. Contact support with log output

---

## Post-Deployment Notes

### Monitoring Checklist

Create monitoring tasks for the team:

**Daily**:
- [ ] Check idle prevention logs exist
- [ ] Verify no errors in application logs
- [ ] Monitor resource utilization (expect increases)

**Weekly**:
- [ ] Review Oban job completion rates
- [ ] Check for any performance degradation
- [ ] Verify Oracle doesn't flag instance for reclamation

**Monthly**:
- [ ] Analyze resource utilization trends
- [ ] Confirm 95th percentile CPU > 20%
- [ ] Update documentation if needed

### Configuration Adjustments

If resource usage is too high/low after deployment:

**To reduce load**:
1. Increase `@check_interval_ms` in `idle_prevention.ex` (default: 5 minutes)
2. Reduce `@memory_allocation_mb` (default: 100MB)
3. Reduce number of parallel tasks in worker

**To increase load**:
1. Decrease `@check_interval_ms`
2. Increase `@memory_allocation_mb`
3. Increase parallel task count
4. Decrease Oban job interval (currently every 3 hours)

### Future Enhancements

Consider for future iterations:
- [ ] Adaptive load based on actual utilization
- [ ] Metrics export to monitoring system
- [ ] Custom load strategies
- [ ] Performance dashboards
- [ ] Alert thresholds

---

## Support

### Getting Help

If deployment fails:

1. **Check logs first**: Most issues are in application logs
2. **Review checklist**: Go through verification steps
3. **Refer to troubleshooting**: Common issues documented above
4. **Test health endpoint**: Useful for quick diagnostics

### Log Locations

Common log paths:
- `/path/to/uptrack/logs/production.log`
- `/path/to/uptrack/logs/*.log` (all logs)
- `journalctl -u uptrack` (systemd logs)

### Useful Commands

```bash
# Check compilation
MIX_ENV=prod mix compile

# Check application configuration
iex -S mix phx.server

# Check database connectivity
iex> Uptrack.AppRepo.query("SELECT 1", [])

# Check Oban status
iex> Oban.check_repository(Uptrack.ObanRepo)

# Monitor resource usage
top -p $(pgrep -f beam)
```

---

## Deployment Confirmation

After successful deployment, please confirm:

- [ ] Application deployed and running
- [ ] IdlePrevention GenServer started
- [ ] First cycle completed (check within 5 minutes)
- [ ] Health endpoint shows idle prevention stats
- [ ] No errors or warnings in logs
- [ ] Resource utilization increased as expected
- [ ] Oban jobs scheduled correctly

Once all items are confirmed, deployment is complete and the instance is protected from Oracle's idle reclamation policy.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-20
**Applicable To**: indiastrong, india-week
**Status**: Ready for Deployment
