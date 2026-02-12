# Uptrack API Collection

This is a [Bruno](https://www.usebruno.com/) API collection for testing the Uptrack API.

## Getting Started

1. Install Bruno from https://www.usebruno.com/
2. Open Bruno and select "Open Collection"
3. Navigate to this `api-collection` folder
4. Select an environment (Local or Production)

## Environments

- **Local** - http://localhost:4000
- **Production** - https://api.uptrack.dev

## Setting Up Variables

Before testing, configure your environment variables:

1. Click the environment dropdown in Bruno
2. Select your environment
3. Set the secret variables:
   - `heartbeatToken` - Your heartbeat monitor token
   - `sessionCookie` - Your session cookie for authenticated endpoints

## Endpoints

### Health Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /healthz` | Liveness probe (is app running?) |
| `GET /ready` | Readiness probe (are dependencies healthy?) |

### Public Endpoints (No Auth)

| Endpoint | Description |
|----------|-------------|
| `POST /api/heartbeat/:token` | Record heartbeat |
| `HEAD /api/heartbeat/:token` | Lightweight heartbeat |
| `GET /api/badge/:slug` | Status badge (SVG) |
| `GET /api/badge/:slug/uptime` | Uptime badge (SVG) |
| `POST /api/status/:slug/subscribe` | Subscribe to notifications |
| `GET /api/subscribe/verify/:token` | Verify subscription |
| `GET /api/subscribe/unsubscribe/:token` | Unsubscribe |

### Authenticated Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/monitors` | List monitors |
| `POST /api/monitors` | Create monitor |
| `POST /api/monitors/smart-defaults` | Get smart defaults |
| `GET /api/analytics/dashboard` | Dashboard overview stats |
| `GET /api/analytics/monitors/:id` | Monitor-specific analytics |
| `GET /api/analytics/organization/trends` | Organization-wide trends |

## Webhook Alert Channel

The webhook alert channel sends POST requests to your configured URL when incidents occur.

### Configuration

```json
{
  "name": "My Webhook",
  "type": "webhook",
  "config": {
    "url": "https://example.com/webhook",
    "secret": "my-secure-secret-at-least-16-chars",
    "headers": {
      "Authorization": "Bearer token"
    }
  }
}
```

### Webhook Events

- `incident.created` - Monitor went down
- `incident.resolved` - Monitor recovered
- `test` - Test notification

### Signature Verification

When `secret` is configured, each request includes an `X-Uptrack-Signature` header:

```
X-Uptrack-Signature: sha256=<hex-encoded-hmac-sha256>
```

Verify with: `HMAC-SHA256(secret, request_body)`

## Custom Domains

Status pages can be served from custom domains (e.g., `status.example.com`).

### Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/status-pages/:id/domain` | Get domain configuration |
| `PUT /api/status-pages/:id/domain` | Set custom domain |
| `POST /api/status-pages/:id/domain/verify` | Verify domain ownership |
| `DELETE /api/status-pages/:id/domain` | Remove custom domain |

### Setup Process

1. **Set domain** - `PUT /api/status-pages/:id/domain` with `{"custom_domain": "status.example.com"}`
2. **Add DNS records**:
   - TXT record: `_uptrack-verification.status.example.com` → `<verification_token>`
   - CNAME record: `status.example.com` → `status.uptrack.dev`
3. **Verify** - `POST /api/status-pages/:id/domain/verify`
4. SSL certificate is automatically provisioned via Let's Encrypt

## Example cURL Commands

### Send Heartbeat
```bash
curl -X POST https://api.uptrack.dev/api/heartbeat/YOUR_TOKEN \
  -H "Content-Type: application/json" \
  -d '{"status": "success", "execution_time": 1234}'
```

### Get Status Badge
```bash
curl https://api.uptrack.dev/api/badge/my-status-page?style=flat
```

### Subscribe to Updates
```bash
curl -X POST https://api.uptrack.dev/api/status/my-status-page/subscribe \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'
```

## OpenAPI Specification

The full OpenAPI spec is available at:
- Local: http://localhost:4000/api/openapi
- SwaggerUI: http://localhost:4000/api/docs (dev only)
