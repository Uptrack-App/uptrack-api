# HAProxy Configuration

HAProxy handles:
1. **HTTPS termination** (port 443 → Phoenix on port 4000)
2. **HTTP → HTTPS redirect** (port 80 → 443)
3. **Database routing** (port 6432 → Postgres primary via Patroni health check)
4. **Stats dashboard** (port 8404, localhost only)

## Installation

### 1. Install HAProxy (All Nodes)

```bash
# Ubuntu/Debian
apt install haproxy

# NixOS (add to configuration.nix)
services.haproxy.enable = true;
```

### 2. Get SSL Certificate

You have two options:

#### Option A: Cloudflare Origin Certificate (Recommended)

1. Go to Cloudflare Dashboard → SSL/TLS → Origin Server
2. Create Certificate (15 year validity)
3. Download certificate and private key
4. Combine them:

```bash
cat origin-cert.pem origin-key.pem > /etc/haproxy/certs/uptrack.app.pem
chmod 600 /etc/haproxy/certs/uptrack.app.pem
chown haproxy:haproxy /etc/haproxy/certs/uptrack.app.pem
```

#### Option B: Let's Encrypt (Alternative)

```bash
# Install certbot
apt install certbot

# Get certificate (requires port 80 to be available temporarily)
certbot certonly --standalone -d uptrack.app -d www.uptrack.app

# Combine for HAProxy
cat /etc/letsencrypt/live/uptrack.app/fullchain.pem \
    /etc/letsencrypt/live/uptrack.app/privkey.pem \
    > /etc/haproxy/certs/uptrack.app.pem

# Set permissions
chmod 600 /etc/haproxy/certs/uptrack.app.pem
chown haproxy:haproxy /etc/haproxy/certs/uptrack.app.pem

# Auto-renew (add to cron)
0 3 * * * certbot renew --quiet --post-hook "systemctl reload haproxy"
```

### 3. Configure Tailscale IPs

Edit `haproxy.cfg` and replace:
- `100.A.A.A` → Node A's Tailscale IP
- `100.B.B.B` → Node B's Tailscale IP

Find Tailscale IPs:
```bash
tailscale ip -4
```

### 4. Deploy Config

```bash
# Copy to all 3 nodes
scp haproxy.cfg node-a:/etc/haproxy/haproxy.cfg
scp haproxy.cfg node-b:/etc/haproxy/haproxy.cfg
scp haproxy.cfg node-c:/etc/haproxy/haproxy.cfg

# Validate syntax
haproxy -c -f /etc/haproxy/haproxy.cfg

# Restart HAProxy
systemctl restart haproxy
systemctl enable haproxy
```

### 5. Set Stats Password

Edit `haproxy.cfg` line 121:
```
stats auth admin:CHANGE_ME_STATS_PASSWORD
```

Generate password:
```bash
openssl rand -base64 16
```

## How It Works

### HTTPS Traffic Flow

```
Internet
  ↓
Cloudflare (DDoS protection, caching)
  ↓
uptrack.app → Node A, B, or C public IP (round-robin)
  ↓
HAProxy :443 (TLS termination)
  ↓
Phoenix app :4000 (local)
```

### Database Traffic Flow

```
Phoenix app on Node A
  ↓
127.0.0.1:6432 (HAProxy local)
  ↓
HAProxy health check via Patroni REST API
  ├─ GET http://100.A.A.A:8008/primary → 200 OK (is leader)
  └─ GET http://100.B.B.B:8008/primary → 503 (not leader)
  ↓
Routes to: 100.A.A.A:5432 (Postgres primary)
```

**Key:** HAProxy queries Patroni's `/primary` endpoint. Only the current leader returns HTTP 200.

### Failover Behavior

**Scenario:** Node A (primary) dies

1. HAProxy health check on Node A fails (3 consecutive failures = 15 seconds)
2. HAProxy marks Node A as DOWN
3. HAProxy switches to Node B (marked as `backup`)
4. Patroni promotes Node B to primary (≤30 seconds)
5. Node B's `/primary` endpoint starts returning 200
6. **Total downtime:** ~45 seconds (health check + Patroni failover)

## Verification

### Check HAProxy is Running

```bash
systemctl status haproxy

# Expected: "active (running)"
```

### Test HTTPS

```bash
curl -I https://uptrack.app

# Expected: HTTP/2 200
```

### Test Database Routing

```bash
# Should connect to current primary
psql -h 127.0.0.1 -p 6432 -U uptrack -d uptrack_prod -c "SELECT pg_is_in_recovery();"

# Expected: f (false = primary)
```

### Test Health Checks

```bash
# From Node A, check Patroni endpoints
curl -s http://100.A.A.A:8008/primary  # Should return 200 if leader
curl -s http://100.B.B.B:8008/primary  # Should return 503 if replica
```

### View Stats Dashboard

```bash
# Access from localhost only
ssh node-a -L 8404:127.0.0.1:8404

# Then open in browser:
# http://localhost:8404/stats
# Username: admin
# Password: (from haproxy.cfg)
```

## Monitoring

Key metrics from stats page:

- **Backend phoenix_app**: Shows local Phoenix app health
- **Backend postgres_cluster**: Shows which Postgres node is active
- **Session rate**: Current requests/second
- **Queue depth**: Should be 0 (if growing, app is slow)

### Prometheus Integration (Optional)

Enable Prometheus exporter:

```bash
# Add to haproxy.cfg frontend section:
frontend stats_prometheus
    bind 127.0.0.1:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
```

Then scrape: `http://127.0.0.1:8405/metrics`

## Troubleshooting

### "503 Service Unavailable"

**Symptoms:** Browser shows 503 error

**Causes:**
1. Phoenix app not running: `systemctl status uptrack`
2. Phoenix app failing health check: `curl http://127.0.0.1:4000/healthz`
3. HAProxy misconfigured: `haproxy -c -f /etc/haproxy/haproxy.cfg`

### "Cannot connect to database"

**Symptoms:** App logs show connection errors

**Causes:**
1. No Postgres primary available
   ```bash
   patronictl -c /etc/patroni/patroni.yml list uptrack-pg-cluster
   # Should show one Leader
   ```

2. Patroni health check failing
   ```bash
   curl http://100.A.A.A:8008/primary
   # Should return 200 on primary
   ```

3. Firewall blocking Tailscale
   ```bash
   telnet 100.A.A.A 5432
   # Should connect
   ```

### "SSL certificate not valid"

**Cloudflare setup:**
- Use "Full (strict)" SSL mode in Cloudflare dashboard
- Ensure origin certificate includes `uptrack.app` and `*.uptrack.app`

**Let's Encrypt setup:**
- Ensure certbot renewed certificate: `certbot certificates`
- Check certificate: `openssl x509 -in /etc/haproxy/certs/uptrack.app.pem -text -noout`

### HAProxy won't start

```bash
# Check logs
journalctl -u haproxy -f

# Common issues:
# 1. Port already in use
netstat -tuln | grep -E ':(80|443|6432)'

# 2. Certificate file missing
ls -l /etc/haproxy/certs/uptrack.app.pem

# 3. Syntax error
haproxy -c -f /etc/haproxy/haproxy.cfg
```

## Performance Tuning

For high-traffic sites, adjust timeouts:

```
defaults
    timeout connect 3000ms
    timeout client 30000ms
    timeout server 30000ms
```

For WebSocket/long-polling:

```
defaults
    timeout tunnel 1h  # Keep WebSocket connections alive
```

## Security

### Current protections:
- ✅ TLS 1.2+ only (no SSL, TLS 1.0/1.1)
- ✅ Strong cipher suites (ECDHE + AES-GCM)
- ✅ Security headers (HSTS, X-Frame-Options, etc.)
- ✅ Database proxy only on localhost (127.0.0.1:6432)
- ✅ Stats page only on localhost

### Additional hardening:
- Rate limiting (use Cloudflare)
- IP allowlisting for admin pages
- Fail2ban for repeated failed requests

## Load Balancing Algorithms

Current: `roundrobin` (default)

Alternatives:
- `leastconn` - Route to server with fewest connections
- `source` - Sticky sessions based on client IP
- `uri` - Route based on URL path

For most apps, `roundrobin` is fine. Phoenix handles sessions via signed cookies.

## Upgrade Strategy

**Zero-downtime reload:**

```bash
# 1. Test new config
haproxy -c -f /etc/haproxy/haproxy.cfg

# 2. Reload (no connection drops)
systemctl reload haproxy
```

HAProxy's reload is seamless — existing connections continue, new connections use new config.
