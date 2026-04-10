# Change: Improve MCP Server for Anthropic Connector Directory Approval

## Why

Uptrack has been submitted to the Anthropic Claude Connectors Directory. The submission form requires MCP Resources, MCP Prompts, an updated protocol version, Streamable HTTP transport, and tool titles. The current implementation returns empty arrays for resources and prompts, uses an outdated protocol version (`2024-11-05`), and lacks the required metadata. Addressing these gaps maximizes approval chances.

## What Changes

- **Add MCP Resources**: 3 resources exposing read-only data (`uptrack://monitors`, `uptrack://incidents`, `uptrack://dashboard`)
- **Add MCP Prompts**: 3 prompt templates for common uptime monitoring workflows (`daily-report`, `incident-summary`, `monitor-health-check`)
- **Update protocol version**: `2024-11-05` → `2025-11-25` (latest stable)
- **Add `title` field to all tools**: Human-readable titles for directory display
- **Implement Streamable HTTP transport**: `/api/mcp/stream` endpoint supporting SSE + HTTP streaming per MCP spec
- **Add `prompts` capability to initialize response**: Currently only advertises `tools` and `resources`
- **Add write tools**: `create_alert_channel`, `acknowledge_incident` for richer AI workflows

## Impact

- Affected specs: `mcp-server`
- New files:
  - `lib/uptrack/mcp/resources.ex` — resource definitions and data fetching
  - `lib/uptrack/mcp/prompts.ex` — prompt template definitions
  - `lib/uptrack_web/controllers/api/mcp_stream_controller.ex` — Streamable HTTP handler
- Modified files:
  - `lib/uptrack/mcp/json_rpc.ex` — update protocol version constant, add `title` to `define_tool/5`
  - `lib/uptrack/mcp/server.ex` — wire resources/prompts handlers, update capabilities
  - `lib/uptrack/mcp/tools.ex` — add `title` to all tool definitions, add new write tools
  - `lib/uptrack_web/router.ex` — add `/api/mcp/stream` route
