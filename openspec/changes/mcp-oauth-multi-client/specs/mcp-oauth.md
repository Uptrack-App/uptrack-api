# Spec: MCP OAuth — Full Spec Compliance

## Requirements

### REQ-1: Boruta tables must exist in production
**Given** the app is running
**Then** the following tables exist in the `app` schema:
- `clients` — OAuth client registrations
- `tokens` — access tokens, refresh tokens, auth codes
- `scopes` — scope definitions
- `clients_scopes` — join table

### REQ-2: 401 responses include WWW-Authenticate header
**Given** a request to `POST /api/mcp` with no Authorization header
**Then** the response is `401 Unauthorized`
**And** the response includes:
```
WWW-Authenticate: Bearer resource_metadata="https://api.uptrack.app/.well-known/oauth-protected-resource"
```

### REQ-3: Auth server metadata includes registration and CIMD fields
**Given** `GET /.well-known/oauth-authorization-server`
**Then** the response includes:
```json
{
  "registration_endpoint": "https://api.uptrack.app/oauth/register",
  "client_id_metadata_document_supported": true
}
```
**And** all existing fields are preserved

### REQ-4: OAuth authorize shows login then consent
**Given** a browser request to `/oauth/authorize` with valid params
**When** the user is not logged into Uptrack
**Then** the user is redirected to the Uptrack login page
**And** after login, the user is returned to the consent screen

**Given** a browser request to `/oauth/authorize` with valid params
**When** the user is logged into Uptrack
**Then** the consent screen shows:
- The name of the client application
- The requested scopes in human-readable form
- Allow and Deny buttons

**When** the user clicks Allow
**Then** the user is redirected to `redirect_uri?code=...&state=...`

**When** the user clicks Deny
**Then** the user is redirected to `redirect_uri?error=access_denied`

### REQ-5: Client ID Metadata Documents supported
**Given** an authorize request where `client_id` is an HTTPS URL
**Then** the server fetches the URL
**And** validates `client_id` in the document matches the URL exactly
**And** uses `client_name` from the document on the consent screen
**And** validates `redirect_uri` against the document's `redirect_uris`

**Given** an authorize request where `client_id` URL returns non-HTTPS, private IP,
or times out
**Then** the server returns `400 Bad Request` with `error: invalid_client`

### REQ-6: Dynamic Client Registration (RFC7591)
**Given** `POST /oauth/register` with valid JSON body:
```json
{
  "client_name": "My MCP App",
  "redirect_uris": ["https://myapp.example.com/callback"],
  "grant_types": ["authorization_code"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "none"
}
```
**Then** the response is `201 Created` with:
```json
{
  "client_id": "<uuid>",
  "client_name": "My MCP App",
  "redirect_uris": ["https://myapp.example.com/callback"],
  "grant_types": ["authorization_code"],
  "client_id_issued_at": 1234567890
}
```

**Given** `POST /oauth/register` with a `redirect_uri` containing a non-HTTPS,
non-localhost URI
**Then** the response is `400 Bad Request` with `error: invalid_redirect_uri`

**Given** more than 10 registration requests from the same IP in one hour
**Then** the response is `429 Too Many Requests`

### REQ-7: Pre-registered clients for known LLMs
**Given** the `mix uptrack.oauth.seed_clients` task has been run
**Then** a client with `client_id: "claude-ai"` exists with redirect URI
`https://claude.ai/api/auth/oauth/callback`
**And** a client with `client_id: "chatgpt"` exists

### REQ-8: Full OAuth flow produces working MCP token
**Given** a client has a valid `client_id` (pre-registered or dynamically registered)
**When** the full authorize → consent → token exchange flow completes
**Then** the resulting Bearer token works on `POST /api/mcp` to call any tool
**And** tools return data scoped to the user's organization

### REQ-9: API key auth still works (no regression)
**Given** a request to `POST /api/mcp` with `Authorization: Bearer utk_...`
**Then** it authenticates as before (no change to API key path)
