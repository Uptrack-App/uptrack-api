# Spec: Notification Diagnostics

## Metrics Emission

### Writer.write_notification_delivery/3
Writes to VictoriaMetrics via existing vminsert HA setup:
```
uptrack_notification_delivery{channel_type="email",status="delivered"} 1 <timestamp_ms>
uptrack_notification_duration_ms{channel_type="email"} 245 <timestamp_ms>
```

Called from `AlertDeliveryWorker.perform/1` after dispatch. Fire-and-forget via existing Writer pattern. Silently skipped if VictoriaMetrics is not configured.

### Emission point
In `AlertDeliveryWorker.perform/1`:
- Record `start = System.monotonic_time(:millisecond)` before dispatch
- After dispatch result: `duration_ms = System.monotonic_time(:millisecond) - start`
- Call `Writer.write_notification_delivery(channel.type, status, duration_ms)`
- Status is "delivered", "failed", or "skipped" matching existing DeliveryTracker convention

## Metrics Reading

### Reader.get_notification_health/1
Queries VictoriaMetrics vmselect:
- `sum by (channel_type, status) (uptrack_notification_delivery)` over last 7d → counts
- `quantile_over_time(0.95, uptrack_notification_duration_ms{channel_type="..."}[7d])` → p95

Returns map keyed by channel_type with delivered/failed/skipped counts and p95_duration_ms.

## Auto-Cleanup

### DeliveryCleanupWorker
Oban cron worker, daily at 03:00 UTC:
```elixir
DELETE FROM notification_deliveries WHERE inserted_at < now() - interval '7 days'
```
Uses `Ecto.Adapters.SQL.query!/2` for efficient bulk delete.

## Admin Endpoints

### GET /api/admin/notification-health
- Pipeline: api_admin
- Returns VictoriaMetrics aggregates per channel_type

### GET /api/admin/alert-channels?q=&page=&per_page=
- Pipeline: api_admin
- Queries AlertChannel joined with Organization for name
- Supports ILIKE search on channel name and org name
- Paginated, default 25, max 100

### POST /api/admin/test-notification
- Pipeline: api_admin
- Body: `{ "channel_id": "uuid" }`
- Loads channel without org scoping
- Calls `Alerting.send_test_alert(channel)`
- Audit logs `admin.notification_tested` with channel info in metadata
- Returns ok/error

### GET /api/admin/notification-deliveries?channel_type=&status=&page=&per_page=
- Pipeline: api_admin
- Queries notification_deliveries across all orgs
- Joins organization and alert_channel for display names
- Filterable by channel_type and status
- Ordered by inserted_at desc, paginated

## Scenarios

### Delivery emits metrics
- Given: VictoriaMetrics is configured
- When: AlertDeliveryWorker delivers a Slack alert in 150ms
- Then: 2 metric lines written: delivery counter + duration

### Health endpoint returns aggregates
- Given: notifications have been sent over the past 7 days
- When: admin GETs /api/admin/notification-health
- Then: response contains per-channel counts and p95 latency

### Admin sends test
- Given: admin is authenticated, a telegram channel exists
- When: admin POSTs /api/admin/test-notification with that channel_id
- Then: test alert sent, audit log created, response ok=true

### Non-existent channel test
- Given: admin is authenticated
- When: admin POSTs test-notification with invalid id
- Then: 404

### Non-admin rejected
- Given: non-admin user
- When: requests any notification diagnostics endpoint
- Then: 403

### Cleanup removes old deliveries
- Given: notification_deliveries has records older than 7 days
- When: DeliveryCleanupWorker runs
- Then: old records are deleted, recent records remain

### VictoriaMetrics not configured
- Given: vminsert URL is nil
- When: AlertDeliveryWorker completes a delivery
- Then: metric write is silently skipped, delivery still succeeds
