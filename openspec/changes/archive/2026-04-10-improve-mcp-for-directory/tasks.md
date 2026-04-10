# Tasks: Improve MCP Server for Anthropic Connector Directory

## 1. Protocol Version & Tool Titles
- [x] 1.1 Update `@protocol_version` in `json_rpc.ex` from `"2024-11-05"` to `"2025-11-25"`
- [x] 1.2 Add `title` field support to `define_tool/5` in `json_rpc.ex`
- [x] 1.3 Add human-readable `title` to all 11 existing tool definitions in `tools.ex`

## 2. MCP Resources
- [x] 2.1 Create `lib/uptrack/mcp/resources.ex` with 3 resource definitions
- [x] 2.2 Implement `uptrack://monitors` resource — returns all monitors as JSON
- [x] 2.3 Implement `uptrack://incidents` resource — returns recent incidents as JSON
- [x] 2.4 Implement `uptrack://dashboard` resource — returns dashboard stats as JSON
- [x] 2.5 Wire `resources/list` in `server.ex` to call `Resources.definitions()`
- [x] 2.6 Wire `resources/read` in `server.ex` to call `Resources.read(uri, org_id)`

## 3. MCP Prompts
- [x] 3.1 Create `lib/uptrack/mcp/prompts.ex` with 3 prompt template definitions
- [x] 3.2 Implement `daily-report` prompt — briefing on monitor health and incidents
- [x] 3.3 Implement `incident-summary` prompt — summary of a specific incident (requires `monitor_name` argument)
- [x] 3.4 Implement `monitor-health-check` prompt — deep-dive on a monitor (requires `monitor_id` argument)
- [x] 3.5 Wire `prompts/list` in `server.ex` to call `Prompts.definitions()`
- [x] 3.6 Wire `prompts/get` in `server.ex` to call `Prompts.get(name, arguments, org_id)`
- [x] 3.7 Add `"prompts" => %{}` to capabilities in `initialize` response

## 4. Streamable HTTP Transport
- [x] 4.1 ~~SSE endpoint~~ — Decided to skip. Existing HTTP POST at `/api/mcp` qualifies as Streamable HTTP per 2025-11-25 spec.

## 5. New Write Tools
- [x] 5.1 Add `create_alert_channel` tool to `tools.ex` (type, name, destination)
- [x] 5.2 Add `acknowledge_incident` tool to `tools.ex` (incident_id)
- [x] 5.3 Add scope handling for new tools in `oauth/scopes.ex` (`alerts:write`, `incidents:write`)

## 6. Bug Fixes (discovered during testing)
- [x] 6.1 Fix `list_monitors` — returns `%{monitors: [...]}` paginated map, not plain list
- [x] 6.2 Fix `monitor_checks` association — not preloaded by `list_monitors`; handle `%Ecto.Association.NotLoaded{}` gracefully in tools.ex and resources.ex

## 7. Validation
- [x] 7.1 Run `openspec validate improve-mcp-for-directory --strict` — passed
- [x] 7.2 Protocol version `2025-11-25` confirmed via live endpoint
- [x] 7.3 `tools/list` returns titles on all 13 tools — confirmed
- [x] 7.4 `resources/list` returns 3 resources — confirmed
- [x] 7.5 `resources/read` returns correct data for all 3 URIs — confirmed
- [x] 7.6 `prompts/list` returns 3 prompts — confirmed
- [x] 7.7 `prompts/get` returns filled messages for all 3 prompts — confirmed
- [x] 7.8 All tool calls (`list_monitors`, `get_dashboard_stats`, `list_incidents`, `list_alert_channels`, `list_status_pages`) return no errors — confirmed
