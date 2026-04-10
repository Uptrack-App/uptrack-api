# Design: MCP Server Improvements for Directory

## Context

The Anthropic Claude Connectors Directory evaluates MCP servers on: tools (have), resources (missing), prompts (missing), Streamable HTTP transport (missing), protocol version currency, and tool metadata quality. We need to address all gaps without breaking existing OAuth + API key auth.

## Goals / Non-Goals

- Goals: Pass directory review; expose all monitoring data via resources; provide reusable prompts; support modern MCP transport
- Non-Goals: Rewrite authentication layer; add GraphQL or WebSocket; change existing tool signatures

## Decisions

- **Resources as static read endpoints**: Resources are org-scoped — `uptrack://monitors`, `uptrack://incidents`, `uptrack://dashboard`. URIs are fixed (no parameterization) to keep the implementation simple. Content is JSON matching the existing tool response shapes.

- **Prompts with embedded tool calls**: Prompts return `messages` with `role: "user"` and `type: "text"` content that includes natural language context + embedded tool invocation hints. This follows the MCP spec without requiring server-side tool execution at prompt-get time.

- **Streamable HTTP over SSE**: Implement GET `/api/mcp/stream` as an SSE endpoint per the MCP Streamable HTTP spec. POST to the same endpoint routes to the existing `Server.handle_message/3`. The existing `/api/mcp` JSON-RPC endpoint is kept for backward compatibility.

- **Protocol version `2025-03-26`**: This is the latest stable spec as of 2025. The bump is non-breaking — clients negotiating `2024-11-05` still work (MCP is forward-compatible for minor version gaps).

- **`title` field in tool definitions**: Added as a top-level string in the tool map per the MCP spec. Directory UI uses this for display. No impact on existing integrations.

## Risks / Trade-offs

- SSE streaming adds a persistent connection; Phoenix handles this via `Plug.Conn.chunk/2` — low risk on existing Cowboy setup
- Resources expose org data without pagination — acceptable because monitor/incident counts are bounded (users rarely exceed 100 monitors)

## Open Questions

- None — implementation is straightforward given existing auth infrastructure
