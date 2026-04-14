# Design: Admin Notification Diagnostics

## Decision 1: VictoriaMetrics for metrics (no GenServer/ETS)

Write notification delivery metrics to VictoriaMetrics via the existing `Metrics.Writer` — same pattern as monitor checks. All nodes already write to the same VM instance(s), so this is naturally cluster-safe with zero new infrastructure.

**New metrics emitted from `AlertDeliveryWorker.perform/1`:**
- `uptrack_notification_delivery{channel_type="email",status="delivered",org_id="uuid"} 1 <timestamp>` — counter, one per delivery
- `uptrack_notification_duration_ms{channel_type="email"} 245 <timestamp>` — latency

Note: `org_id` label on the delivery counter enables per-organization breakdown. Not added to duration metric to keep cardinality low.

**Queried via `Metrics.Reader`:**
- `sum by (channel_type, status) (uptrack_notification_delivery[7d])` — 7d counts
- `sum by (channel_type, status, org_id) (uptrack_notification_delivery[7d])` — per-org counts
- `quantile_over_time(0.95, uptrack_notification_duration_ms[7d])` by channel_type — p95 latency
- `sum by (channel_type, status) (uptrack_notification_delivery)` with step=1d — daily trend chart data

This adds ~2 metric lines per notification delivery to the existing Batcher flow. Minimal overhead.

## Decision 2: notification_deliveries for delivery log + error breakdown

The `notification_deliveries` table already records every delivery with `error_message`. Use it for:
- Admin delivery log (recent list with error messages, channel names, org names)
- Error breakdown (GROUP BY error_message WHERE status='failed', last 7d)
- Last successful delivery timestamp per channel type (MAX(inserted_at) WHERE status='delivered' GROUP BY channel_type)

These are simple DB queries scoped to the 7-day retention window.

## Decision 3: 7-day retention with auto-cleanup

Add an Oban cron job that deletes `notification_deliveries` older than 7 days. Run daily.

VictoriaMetrics retention is configured at the VM level (already set). Metrics naturally expire.

## Decision 4: Minimal emission — just two lines in AlertDeliveryWorker

After the dispatch result is known in `AlertDeliveryWorker.perform/1`:
```elixir
Writer.write_notification_delivery(channel.type, status, duration_ms, org_id)
```

One new function in `Writer` that formats and writes 2 Prometheus lines. No telemetry events, no handlers, no GenServer. Just a direct write through the existing Writer.

## Decision 5: Admin can test any channel cross-org

`POST /api/admin/test-notification` loads channel without org filter, calls `Alerting.send_test_alert/1`, audit-logs the action.

## Decision 6: Single admin page at /admin/notifications

One page with four sections:
1. **Health cards** — 4 cards (email, slack, discord, telegram) with 7d counts, fail rate, p95 latency, last successful delivery timestamp
2. **Delivery trend chart** — daily delivered/failed counts per channel type over 7 days (line or bar chart)
3. **Channel test table** — all channels across all orgs with Send Test button
4. **Recent deliveries** — last 7 days from notification_deliveries table, filterable, with error breakdown summary at top

## API Shape

### GET /api/admin/notification-health
```json
{
  "channels": {
    "email": {
      "delivered_7d": 312, "failed_7d": 1, "skipped_7d": 5,
      "fail_rate_7d": 0.003,
      "p95_duration_ms": 1200,
      "last_success_at": "2026-04-14T12:00:00Z"
    },
    "slack": { ... },
    "discord": { ... },
    "telegram": { ... }
  },
  "daily_trend": [
    { "date": "2026-04-08", "email_delivered": 45, "email_failed": 0, "slack_delivered": 12, ... },
    { "date": "2026-04-09", ... },
    ...
  ],
  "error_breakdown": [
    { "channel_type": "email", "error_message": "SMTP connection refused", "count": 3 },
    { "channel_type": "discord", "error_message": "429 rate limited", "count": 1 }
  ],
  "per_org": [
    { "org_id": "uuid", "org_name": "Acme Inc", "delivered": 200, "failed": 1 },
    { "org_id": "uuid", "org_name": "Beta Corp", "delivered": 50, "failed": 0 }
  ]
}
```

### GET /api/admin/alert-channels?q=&page=&per_page=
Paginated list of all channels across all orgs with org name, active status, type.

### POST /api/admin/test-notification
Request: `{ "channel_id": "uuid" }`
Response: `{ "ok": true, "channel_type": "email", "channel_name": "Ops Email" }`

### GET /api/admin/notification-deliveries?channel_type=&status=&page=&per_page=
Paginated list from notification_deliveries, newest first, with org and channel names.
