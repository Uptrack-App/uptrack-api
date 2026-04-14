## 1. Metrics Emission

- [x] 1.1 Add `Writer.write_notification_delivery(channel_type, status, duration_ms, org_id)` to `Metrics.Writer` — writes 2 Prometheus lines: `uptrack_notification_delivery{channel_type,status,org_id} 1` and `uptrack_notification_duration_ms{channel_type} duration_ms`
- [x] 1.2 Call `Writer.write_notification_delivery/4` from `AlertDeliveryWorker.perform/1` after dispatch completes (both success and failure paths), measuring duration from before dispatch to after

## 2. Metrics Reading

- [x] 2.1 Add `Reader.get_notification_stats(days \\ 7)` — queries VictoriaMetrics for delivery counts grouped by channel_type and status over last N days. Returns `%{channel_type => %{delivered: n, failed: n, skipped: n}}`
- [x] 2.2 Add `Reader.get_notification_latency(days \\ 7)` — queries p95 duration per channel_type. Returns `%{channel_type => p95_ms}`
- [x] 2.3 Add `Reader.get_notification_daily_trend(days \\ 7)` — queries daily delivery counts per channel_type and status using `query_range` with step=1d. Returns list of `%{date, channel_type, status, count}`
- [x] 2.4 Add `Reader.get_notification_per_org_stats(days \\ 7)` — queries delivery counts grouped by org_id and status. Returns list of `%{org_id, delivered, failed}`

## 3. DB Queries (notification_deliveries)

- [x] 3.1 Add `DeliveryTracker.list_platform_deliveries(opts)` — lists across all orgs with optional filters (channel_type, status, page, per_page), joins organization and alert_channel for names, ordered by inserted_at desc
- [x] 3.2 Add `DeliveryTracker.get_error_breakdown(days \\ 7)` — groups failed deliveries by channel_type and error_message, returns list of `%{channel_type, error_message, count}`, top 20
- [x] 3.3 Add `DeliveryTracker.get_last_success_per_channel_type(days \\ 7)` — returns `%{channel_type => last_success_at}` via MAX(inserted_at) WHERE status='delivered'
- [x] 3.4 Add `Admin.list_all_channels(query_string, opts)` — queries all AlertChannels across orgs with organization name join, ILIKE search, paginated

## 4. Auto-Cleanup

- [x] 4.1 Create `Uptrack.Alerting.DeliveryCleanupWorker` — Oban cron worker (daily 03:00 UTC) that deletes notification_deliveries older than 7 days via bulk SQL delete

## 5. Admin Endpoints

- [x] 5.1 Add `notification_health/2` to `AdminController` — aggregates: Reader stats + Reader latency + Reader daily trend + Reader per-org stats + DeliveryTracker error breakdown + DeliveryTracker last success timestamps. Returns combined JSON
- [x] 5.2 Add `list_all_channels/2` to `AdminController` — calls `Admin.list_all_channels/2` with search/pagination params
- [x] 5.3 Add `test_notification/2` to `AdminController` — loads channel by id (no org filter), calls `Alerting.send_test_alert(channel)`, audit logs `admin.notification_tested`, returns result
- [x] 5.4 Add `list_notification_deliveries/2` to `AdminController` — calls `DeliveryTracker.list_platform_deliveries/1` with filters
- [x] 5.5 Add render functions to `AdminJSON` for all four endpoints
- [x] 5.6 Add routes to `/api/admin` scope: `get "/notification-health"`, `get "/alert-channels"`, `post "/test-notification"`, `get "/notification-deliveries"`
- [x] 5.7 Add `admin.notification_tested` to AuditLog actions list
- [x] 5.8 Write controller tests

## 6. Frontend — API Client

- [x] 6.1 Add TypeScript types and API client functions in `api.ts`: `adminGetNotificationHealth()`, `adminListAlertChannels(q, page, perPage)`, `adminTestNotification(channelId)`, `adminListNotificationDeliveries(filters)`

## 7. Frontend — Admin Notifications Page

- [x] 7.1 Create `/admin/notifications` route with admin guard
- [x] 7.2 Build health cards section: 4 cards per channel type showing 7d delivered/failed/skipped counts, fail rate %, p95 latency, last successful delivery timestamp. Color: green <5% fail, yellow <20%, red >=20%, gray if no data
- [x] 7.3 Build delivery trend chart: daily bar/line chart over 7 days, one series per channel_type, showing delivered vs failed. Use a lightweight chart lib (recharts or similar already in deps)
- [x] 7.4 Build per-organization health table: list orgs with delivered/failed counts, sorted by most failures first
- [x] 7.5 Build error breakdown summary: grouped list of recent errors with count and channel type
- [x] 7.6 Build channel test table: searchable list of all channels with type, org name, active badge, "Send Test" button with inline loading/success/error state
- [x] 7.7 Build delivery log section: paginated table with channel_type and status dropdown filters, shows timestamp, channel type, event type, status, error message, org name
- [x] 7.8 Auto-refresh health data every 30s via react-query refetchInterval
- [x] 7.9 Register route in `routeTree.gen.ts` and add "Notifications" link in sidebar under admin section

## 8. Manual Verification

- [ ] 8.1 Send a test notification through each channel type, verify delivery appears in log and health cards update
- [ ] 8.2 Verify daily trend chart shows data points
- [ ] 8.3 Verify per-org breakdown shows correct org attribution
- [ ] 8.4 Verify error breakdown groups failures correctly
- [ ] 8.5 Verify auto-cleanup removes old deliveries
- [ ] 8.6 Verify non-admin users cannot access the page or endpoints
