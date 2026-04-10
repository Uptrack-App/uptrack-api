# Design: MCP OAuth — Full Spec Compliance for All LLM Clients

## Context

MCP 2025-11-25 specifies three client registration strategies, in priority order:
1. **Client ID Metadata Documents** — client uses an HTTPS URL as `client_id`; server
   fetches the URL to get metadata. Preferred by Claude.ai.
2. **Dynamic Client Registration (RFC7591)** — client POSTs to `/oauth/register` to get
   credentials. Used by ChatGPT, Mistral, and clients with no prior relationship.
3. **Pre-registration** — client has hardcoded `client_id`/`client_secret`. Used as
   fallback or for known trusted clients.

We implement all three, plus the required discovery infrastructure.

## Architecture

```
User browser
    │
    ▼
/oauth/authorize?client_id=...&redirect_uri=...&scope=...&code_challenge=...
    │
    ├─ client_id is HTTPS URL?
    │       ├─ YES → fetch URL, validate metadata doc (Client ID Metadata Doc)
    │       └─ NO  → look up in Boruta clients table (pre-registered or dynamic)
    │
    ▼
Show Uptrack login (magic link / Google / GitHub)
    │
    ▼
Show consent screen: "{client_name} wants access to {scopes}"
    │
    ▼
User approves → generate auth code (Boruta)
    │
    ▼
Redirect to redirect_uri?code=...&state=...
    │
    ▼
Client POSTs to /oauth/token → Boruta issues access token
    │
    ▼
Client uses token as Bearer on /api/mcp requests
```

## Key Decisions

### Boruta for token issuance, custom logic for client resolution
Boruta handles: auth code generation, PKCE validation, token issuance, token validation,
refresh tokens. We handle: client resolution (metadata docs, dynamic registration), login
UI, consent UI.

### Consolidated Boruta migration
Rather than copying all 15 Boruta migration files individually, we create one migration
that calls each `Boruta.Migrations.*.__using__/1` macro in order. This keeps our
`priv/repo/migrations/` clean and ties Boruta version to our deps.

### Schema prefix: `app`
AppRepo uses search_path `app`. Boruta's tables must be created with `@prefix "app"` in
the migration, otherwise Postgres won't find them.

### Consent page: controller-based (not LiveView)
OAuth consent is a simple form POST — no real-time updates needed. A regular Phoenix
controller + EEx template is simpler, has no JS dependency, and works in all browsers
including embedded webviews that LLM clients may use.

### Dynamic registration: open but rate-limited
We accept any `POST /oauth/register` with valid JSON per RFC7591. No allowlist. Rate
limited to 10 registrations per IP per hour to prevent abuse. Dynamic clients are
`confidential: false` (public clients) with short-lived tokens (1 hour access, 30 day
refresh).

### Client ID Metadata Documents: fetch at authorize time
When `client_id` is an HTTPS URL, we fetch it at `/oauth/authorize` request time. We
do not pre-cache. SSRF protection: only allow `https://` URLs, reject private IP ranges
(RFC1918 + loopback), timeout at 3 seconds.

### Pre-registered clients for known LLMs
| Client | client_id | redirect_uri |
|--------|-----------|--------------|
| Claude.ai | `claude-ai` | `https://claude.ai/api/auth/oauth/callback` |
| ChatGPT | `chatgpt` | `https://chat.openai.com/aip/plugin-some-id/oauth/callback` |

These are seeded via a migration or a Mix task, not hardcoded in app config.

### WWW-Authenticate header (already implemented)
```
WWW-Authenticate: Bearer resource_metadata="https://api.uptrack.app/.well-known/oauth-protected-resource"
```
Deployed with the next release.

## Auth Server Metadata additions

Current `/.well-known/oauth-authorization-server`:
```json
{
  "issuer": "https://api.uptrack.app",
  "authorization_endpoint": "https://api.uptrack.app/oauth/authorize",
  "token_endpoint": "https://api.uptrack.app/oauth/token",
  "revocation_endpoint": "https://api.uptrack.app/oauth/revoke",
  "code_challenge_methods_supported": ["S256"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "response_types_supported": ["code"],
  "scopes_supported": [...],
  "token_endpoint_auth_methods_supported": ["client_secret_post", "client_secret_basic"]
}
```

After this change, also includes:
```json
{
  "registration_endpoint": "https://api.uptrack.app/oauth/register",
  "client_id_metadata_document_supported": true
}
```

## Elixir Principles

- **Contexts over controllers**: client registration logic lives in `Uptrack.OAuth`
  context, not in the controller. Controllers are thin.
- **Pattern matching for client_id type**: `authorize_controller.ex` dispatches on
  whether `client_id` is a URL or plain string using pattern matching, no conditionals.
- **Supervised HTTP client**: metadata document fetching uses `Req` (already a dep) with
  explicit timeouts. Wrapped in `Task.async` with `Task.await` + timeout for SSRF safety.
- **Migration as a module**: the Boruta migration file calls each upstream migration
  macro in order — readable and auditable.
- **No global state**: dynamic clients stored in Boruta DB, not ETS or Agent.

## Risks / Trade-offs

- **SSRF on metadata fetch**: mitigated by URL validation (HTTPS only, no private IPs,
  3s timeout)
- **Boruta migration on live DB**: additive only (new tables), zero downtime risk
- **Open dynamic registration**: any client can register; mitigated by rate limiting and
  short token TTLs for public clients
- **ChatGPT redirect URI**: OpenAI doesn't publish the exact redirect URI format; we use
  the known pattern from their plugin OAuth docs and can update post-launch
