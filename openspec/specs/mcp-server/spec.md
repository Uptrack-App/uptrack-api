# mcp-server Specification

## Purpose
TBD - created by archiving change improve-mcp-for-directory. Update Purpose after archive.
## Requirements
### Requirement: MCP Resources — Monitor List
The system SHALL expose an `uptrack://monitors` resource returning all org monitors as structured JSON.

#### Scenario: List resources includes uptrack://monitors
- **WHEN** a client calls `resources/list`
- **THEN** the response SHALL include a resource with `uri: "uptrack://monitors"`, `name: "Monitors"`, `mimeType: "application/json"`

#### Scenario: Read monitors resource returns all monitors
- **WHEN** a client calls `resources/read` with `uri: "uptrack://monitors"`
- **THEN** the response SHALL return `contents` with JSON array of monitors including `id`, `name`, `url`, `status`, `uptime_percentage`

#### Scenario: Unauthorized access rejected
- **WHEN** a client calls `resources/read` without a valid auth token
- **THEN** the server SHALL return a JSON-RPC error with code `-32001` (Unauthorized)

### Requirement: MCP Resources — Incident List
The system SHALL expose an `uptrack://incidents` resource returning recent org incidents as structured JSON.

#### Scenario: List resources includes uptrack://incidents
- **WHEN** a client calls `resources/list`
- **THEN** the response SHALL include a resource with `uri: "uptrack://incidents"`, `name: "Recent Incidents"`, `mimeType: "application/json"`

#### Scenario: Read incidents resource returns recent incidents
- **WHEN** a client calls `resources/read` with `uri: "uptrack://incidents"`
- **THEN** the response SHALL return `contents` with JSON array of the 50 most recent incidents including `id`, `monitor_name`, `status`, `started_at`, `resolved_at`, `cause`

### Requirement: MCP Resources — Dashboard Stats
The system SHALL expose an `uptrack://dashboard` resource returning aggregate org stats as structured JSON.

#### Scenario: List resources includes uptrack://dashboard
- **WHEN** a client calls `resources/list`
- **THEN** the response SHALL include a resource with `uri: "uptrack://dashboard"`, `name: "Dashboard Stats"`, `mimeType: "application/json"`

#### Scenario: Read dashboard resource returns stats
- **WHEN** a client calls `resources/read` with `uri: "uptrack://dashboard"`
- **THEN** the response SHALL return `contents` with JSON object including `total_monitors`, `monitors_up`, `monitors_down`, `average_uptime_30d`, `active_incidents`

### Requirement: MCP Prompts — Daily Report
The system SHALL provide a `daily-report` prompt that guides an AI to generate a daily uptime briefing.

#### Scenario: List prompts includes daily-report
- **WHEN** a client calls `prompts/list`
- **THEN** the response SHALL include a prompt with `name: "daily-report"`, a human-readable `description`, and no required arguments

#### Scenario: Get daily-report returns messages
- **WHEN** a client calls `prompts/get` with `name: "daily-report"`
- **THEN** the response SHALL return `messages` array with `role: "user"` instructing the AI to call `get_dashboard_stats` and `list_incidents` to produce a daily status report

### Requirement: MCP Prompts — Incident Summary
The system SHALL provide an `incident-summary` prompt that guides an AI to summarize a specific incident.

#### Scenario: List prompts includes incident-summary
- **WHEN** a client calls `prompts/list`
- **THEN** the response SHALL include a prompt with `name: "incident-summary"` and an `arguments` array containing a required `monitor_name` string argument

#### Scenario: Get incident-summary with monitor_name
- **WHEN** a client calls `prompts/get` with `name: "incident-summary"` and `arguments: {monitor_name: "api.example.com"}`
- **THEN** the response SHALL return `messages` instructing the AI to call `list_incidents` filtered by the given monitor name and summarize findings

### Requirement: MCP Prompts — Monitor Health Check
The system SHALL provide a `monitor-health-check` prompt that guides an AI to perform a deep-dive on a single monitor.

#### Scenario: List prompts includes monitor-health-check
- **WHEN** a client calls `prompts/list`
- **THEN** the response SHALL include a prompt with `name: "monitor-health-check"` and an `arguments` array containing a required `monitor_id` string argument

#### Scenario: Get monitor-health-check with monitor_id
- **WHEN** a client calls `prompts/get` with `name: "monitor-health-check"` and `arguments: {monitor_id: "mon_123"}`
- **THEN** the response SHALL return `messages` instructing the AI to call `get_monitor` and `get_monitor_analytics` for the given ID and produce a health assessment

### Requirement: Protocol Version Update
The system SHALL advertise MCP protocol version `2025-11-25` in the `initialize` response.

#### Scenario: Initialize returns updated protocol version
- **WHEN** a client sends an `initialize` request
- **THEN** `protocolVersion` in the response SHALL be `"2025-11-25"`

### Requirement: Prompts Capability Advertised
The system SHALL include `"prompts": {}` in the `capabilities` field of the `initialize` response.

#### Scenario: Initialize capabilities include prompts
- **WHEN** a client sends an `initialize` request
- **THEN** the `capabilities` object SHALL contain keys `"tools"`, `"resources"`, and `"prompts"`

### Requirement: Tool Title Field
All MCP tools SHALL include a human-readable `title` field in their definition.

#### Scenario: tools/list includes title on all tools
- **WHEN** a client calls `tools/list`
- **THEN** every tool in the response SHALL have a non-empty `title` string (e.g., `"List Monitors"`, `"Create Monitor"`)

### Requirement: Streamable HTTP Transport
The system SHALL provide a Streamable HTTP endpoint at `GET /api/mcp/stream` for SSE-based MCP connections.

#### Scenario: SSE connection established
- **WHEN** a client sends `GET /api/mcp/stream` with `Accept: text/event-stream` and valid auth
- **THEN** the server SHALL respond with `Content-Type: text/event-stream` and keep the connection open

#### Scenario: POST to stream endpoint processes message
- **WHEN** a client sends `POST /api/mcp/stream` with a valid JSON-RPC message body and valid auth
- **THEN** the server SHALL process the message and return the JSON-RPC response (same as `/api/mcp`)

#### Scenario: Existing /api/mcp endpoint unchanged
- **WHEN** a client sends `POST /api/mcp` with a valid JSON-RPC message
- **THEN** the server SHALL continue to respond correctly (backward compatible)

### Requirement: New Write Tool — Create Alert Channel
The system SHALL provide a `create_alert_channel` MCP tool to add a new alert channel.

#### Scenario: Create email alert channel
- **WHEN** `create_alert_channel` is called with `type: "email"`, `name: "Ops Team"`, `destination: "ops@example.com"`
- **THEN** the system SHALL create the channel and return its `id` and confirmation

#### Scenario: Invalid type rejected
- **WHEN** `create_alert_channel` is called with an unsupported `type`
- **THEN** the system SHALL return an error listing supported types

### Requirement: New Write Tool — Acknowledge Incident
The system SHALL provide an `acknowledge_incident` MCP tool to acknowledge an active incident.

#### Scenario: Acknowledge active incident
- **WHEN** `acknowledge_incident` is called with a valid `incident_id`
- **THEN** the system SHALL mark the incident as acknowledged and return confirmation

#### Scenario: Incident not found
- **WHEN** `acknowledge_incident` is called with an unknown `incident_id`
- **THEN** the system SHALL return a descriptive error

### Requirement: Backwards Compatibility
All existing tools, authentication methods, and the `/api/mcp` endpoint SHALL remain unchanged.

#### Scenario: Existing tools/call unchanged
- **WHEN** any existing tool is called via `/api/mcp`
- **THEN** the response SHALL be identical to pre-change behavior

#### Scenario: API key auth still works
- **WHEN** a client authenticates with an API key Bearer token
- **THEN** the server SHALL authenticate successfully and provide `:all` scope access

