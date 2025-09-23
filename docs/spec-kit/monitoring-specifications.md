# Monitoring Specifications

*Executable specifications for Uptrack's core monitoring functionality*

## Monitor Types Specification

### HTTP/HTTPS Monitoring
```yaml
spec_id: monitor_http
capability: HTTP endpoint monitoring
requirements:
  - Support GET requests to any HTTP/HTTPS URL
  - Follow redirects (max 5 hops)
  - Custom headers support
  - Timeout configuration (5-300 seconds)
  - Status code validation (200-299 = success by default)
  - Response time measurement (millisecond precision)
  - Response body size limits (10KB max storage)

behavior:
  check_frequency: 30s to 24h (user configurable)
  timeout_default: 30s
  user_agent: "Uptrack Monitor/1.0"

success_criteria:
  - HTTP status 200-299 (unless custom range specified)
  - Response received within timeout window
  - No transport/connection errors

failure_modes:
  - Connection timeout
  - DNS resolution failure
  - TLS/SSL certificate errors
  - HTTP error status codes (400+, 500+)
  - Response timeout
```

### TCP Port Monitoring
```yaml
spec_id: monitor_tcp
capability: TCP port connectivity testing
requirements:
  - Connect to any host:port combination
  - IPv4 and IPv6 support
  - Connection timeout configuration
  - No data exchange (connection test only)

behavior:
  check_frequency: 30s to 24h (user configurable)
  timeout_default: 10s

success_criteria:
  - TCP connection established successfully
  - Connection closed cleanly

failure_modes:
  - Connection refused
  - Connection timeout
  - Network unreachable
  - DNS resolution failure
```

### Keyword Monitoring
```yaml
spec_id: monitor_keyword
capability: HTTP response content validation
requirements:
  - All HTTP monitoring capabilities (inherits from monitor_http)
  - Search for specific text/keyword in response body
  - Case-sensitive string matching
  - Keyword configuration per monitor

behavior:
  inherits: monitor_http
  additional_validation: keyword presence check

success_criteria:
  - HTTP request succeeds (per monitor_http spec)
  - Specified keyword found in response body

failure_modes:
  - Any HTTP failure (per monitor_http spec)
  - Keyword not found in response body
```

## Check Execution Specification

### Scheduler Behavior
```yaml
spec_id: check_scheduler
capability: Automated monitor execution
requirements:
  - Execute checks for all active monitors
  - Respect individual monitor intervals
  - Distribute check load evenly
  - Handle monitor configuration changes
  - Graceful handling of disabled monitors

behavior:
  base_frequency: 30s (scheduler runs every 30s)
  jitter: ±5s (prevent thundering herd)
  backoff: None (always respect user-defined intervals)

execution_rules:
  - Only check monitors marked as "active"
  - Skip checks if previous check still running
  - Respect monitor.interval setting
  - Update last_check timestamp on completion
```

### Result Storage
```yaml
spec_id: check_storage
capability: Time-series data persistence
requirements:
  - Store all check results in TimescaleDB hypertables
  - Separate storage by user tier (free/solo/team)
  - Compress data after 7 days
  - Apply retention policies automatically
  - Maintain data integrity during high load

schema:
  tables:
    - results.monitor_results_free (120d retention)
    - results.monitor_results_solo (455d retention)
    - results.monitor_results_team (455d retention)

  fields:
    - ts: timestamp (partition key)
    - monitor_id: reference to monitor
    - account_id: reference to user account
    - ok: boolean success flag
    - status_code: HTTP status (nullable)
    - err_kind: error classification (nullable)
    - total_ms: response time in milliseconds
    - probe_region: geographic origin (future)

indexing:
  - (monitor_id, ts) for monitor-specific queries
  - (account_id, ts) for user dashboard queries
  - ts for time-range queries
```

## Alert Specification

### Incident Detection
```yaml
spec_id: incident_detection
capability: Automated incident creation and resolution
requirements:
  - Create incident on first failed check
  - Track incident duration
  - Auto-resolve when monitor recovers
  - Store incident metadata
  - Link to first and last failing checks

behavior:
  detection_threshold: 1 failed check
  resolution_threshold: 1 successful check
  incident_data:
    - start_time: first failure timestamp
    - end_time: resolution timestamp (nullable)
    - duration: calculated on resolution
    - cause: error message from first failure
    - status: "ongoing" | "resolved"

state_transitions:
  monitor_up → monitor_down: create incident
  monitor_down → monitor_up: resolve incident
  monitor_down → monitor_down: update incident metadata
```

### Notification Delivery
```yaml
spec_id: alert_delivery
capability: Multi-channel incident notifications
requirements:
  - Send alerts within 30 seconds of incident creation
  - Send resolution notifications
  - Support multiple notification channels
  - Retry failed deliveries (3 attempts max)
  - Track delivery success/failure

channels:
  - email: SMTP delivery
  - slack: Webhook to Slack channels
  - webhook: HTTP POST to custom endpoints
  - telegram: Telegram bot API

behavior:
  max_delivery_time: 30s
  retry_attempts: 3
  retry_backoff: exponential (1s, 2s, 4s)

delivery_tracking:
  - attempt_count: number of tries
  - last_attempt_at: timestamp
  - delivery_status: "pending" | "delivered" | "failed"
```

## Dashboard Specification

### Real-time Updates
```yaml
spec_id: dashboard_realtime
capability: Live monitoring status display
requirements:
  - Show current status of all user monitors
  - Update automatically when checks complete
  - Display last check time and result
  - Show ongoing incidents
  - Real-time uptime percentages

update_mechanism: Phoenix LiveView + PubSub
refresh_frequency: "immediate on check completion"
data_freshness: < 5s lag from check completion

display_elements:
  - monitor_status: "up" | "down" | "unknown"
  - last_check_time: relative timestamp
  - response_time: latest measurement
  - uptime_percentage: calculated from recent history
  - incident_count: active incidents
```

### Historical Analytics
```yaml
spec_id: dashboard_analytics
capability: Historical performance visualization
requirements:
  - Query TimescaleDB rollups (never raw data)
  - Support multiple time ranges (24h, 7d, 30d, 90d)
  - Display uptime trends
  - Show response time distributions
  - Incident frequency analysis

query_strategy:
  - 24h view: query 1-minute rollups
  - 7d view: query 5-minute rollups
  - 30d+ view: query daily rollups

performance_targets:
  - chart_load_time: < 2s for 30-day view
  - data_points: < 1000 per chart
  - cache_duration: 5 minutes for aggregated data
```

## Integration Specification

### Webhook Integration
```yaml
spec_id: webhook_integration
capability: Custom HTTP notification delivery
requirements:
  - POST JSON payloads to user-defined URLs
  - Include incident details and monitor metadata
  - Support custom headers and authentication
  - Retry failed deliveries with backoff
  - Validate webhook URLs

payload_format:
  incident_created:
    event: "incident.created"
    monitor: {...monitor_object...}
    incident: {...incident_object...}
    timestamp: "ISO8601"

  incident_resolved:
    event: "incident.resolved"
    monitor: {...monitor_object...}
    incident: {...incident_object...}
    timestamp: "ISO8601"

delivery_requirements:
  - timeout: 30s
  - retries: 3 attempts
  - backoff: exponential
  - success_codes: 200-299
```

### Status Page Integration
```yaml
spec_id: status_page
capability: Public status display
requirements:
  - Public URLs for status pages
  - Group monitors by status page
  - Show aggregate status (all up = green, any down = red)
  - Historical incident data
  - Customizable branding

visibility:
  - public: no authentication required
  - seo_friendly: proper meta tags and structure
  - mobile_responsive: works on all devices

data_display:
  - current_status: calculated from all monitors
  - monitor_list: shows individual monitor status
  - incident_history: last 30 days of incidents
  - uptime_stats: rolling percentages
```

---

*These specifications define the exact behavior expected from Uptrack's monitoring system. All implementations must conform to these requirements.*