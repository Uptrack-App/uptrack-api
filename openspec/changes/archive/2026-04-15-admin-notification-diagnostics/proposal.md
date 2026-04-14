# Proposal: Admin Notification Diagnostics

## Why

The platform sends alerts via email, Slack, Discord, and Telegram. Today there is no way for a platform admin to see whether these notification channels are healthy — you only discover failures when a user reports a missed alert. We need an admin-facing diagnostics page that surfaces delivery health, recent failures, and lets admins send test messages through any channel.

## What changes

### New capability: notification-diagnostics

A telemetry-driven notification health monitoring system for platform admins.

**Telemetry layer:**
- Emit `[:uptrack, :notification, :delivery]` telemetry events from each alert module with measurements (duration_ms) and metadata (channel_type, status, error)
- Attach handler to Oban's built-in `[:oban, :job, :stop]` and `[:oban, :job, :exception]` for the `email_critical` queue
- Aggregate metrics in an ETS-backed GenServer (`Uptrack.Alerting.NotificationStats`) — rolling counters per channel type: delivered/failed/total count, p50/p95 latency, last delivery timestamp, last error

**API layer:**
- `GET /api/admin/notification-health` — real-time stats from ETS + 7-day historical from `notification_deliveries`
- `GET /api/admin/alert-channels` — list all channels across all orgs (for the test table)
- `POST /api/admin/test-notification` — send test through any channel (reuses existing `send_test_alert/1`)
- `GET /api/admin/notification-deliveries` — recent deliveries across all orgs with filtering

**Frontend:**
- `/admin/notifications` page with:
  - Health cards per channel type (real-time stats from telemetry)
  - All-channels table with "Send Test" button per row
  - Recent delivery log with status/error filtering
