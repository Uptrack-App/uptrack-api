# Change: MCP OAuth — Full Spec Compliance for All LLM Clients

## Why

The current MCP server authenticates only via API keys. OAuth infrastructure (Boruta) is
configured in code but its database migrations were never run, meaning OAuth is entirely
non-functional in production. As a result:

- Claude.ai custom connector cannot connect (no OAuth flow)
- Claude.ai Connectors Directory cannot work (depends on OAuth)
- ChatGPT and Mistral Le Chat cannot connect (need Dynamic Client Registration)

The MCP 2025-11-25 spec mandates specific OAuth 2.1 flows (RFC9728, RFC8414, RFC7591)
for any HTTP-based server that wants to be usable by standard MCP clients. We have the
endpoints but no backing database, no consent UI, and no dynamic registration.

## What Changes

### Phase 1 — Make OAuth work at all
- Run Boruta migrations to create `clients`, `tokens`, `scopes` tables in the `app` schema
- Fix `WWW-Authenticate` header on 401 responses (already done in code, needs deploy)
- Add `registration_endpoint` and `client_id_metadata_document_supported` to
  `/.well-known/oauth-authorization-server` metadata
- Build the OAuth consent UI (authorize page shown to user during OAuth flow)
- Create pre-registered OAuth clients for Claude.ai and ChatGPT with known redirect URIs

### Phase 2 — Dynamic Client Registration (RFC7591)
- Implement `POST /oauth/register` endpoint — allows any MCP client (ChatGPT, Mistral,
  future clients) to self-register without manual setup
- Return `registration_endpoint` in auth server metadata
- Validate and store dynamic client registrations via Boruta Admin API

### Phase 3 — Client ID Metadata Documents
- Support URL-formatted `client_id` in the authorize endpoint
- When `client_id` is an HTTPS URL, fetch the metadata document, validate it, extract
  `redirect_uris` and `client_name` for the consent screen
- Add `client_id_metadata_document_supported: true` to auth server metadata

## Impact

- **New migrations**: Boruta tables (`clients`, `tokens`, `scopes`, related indexes)
- **New files**:
  - `lib/uptrack_web/controllers/oauth/consent_controller.ex` — consent UI
  - `lib/uptrack_web/controllers/oauth/registration_controller.ex` — RFC7591 dynamic registration
  - `lib/uptrack_web/live/oauth_authorize_live.ex` — or controller-based consent page
  - `priv/repo/migrations/*_create_boruta_tables.exs` — consolidated Boruta migration
- **Modified files**:
  - `lib/uptrack_web/controllers/oauth/auth_server_metadata_controller.ex` — add `registration_endpoint`, `client_id_metadata_document_supported`
  - `lib/uptrack_web/controllers/oauth/authorize_controller.ex` — handle URL client_id, show consent
  - `lib/uptrack_web/router.ex` — add `/oauth/register` route
  - `lib/uptrack_web/plugs/mcp_auth.ex` — `WWW-Authenticate` header (already done)

## Non-Goals

- We do not implement OpenID Connect (OIDC) — OAuth 2.1 only
- We do not support `client_credentials` grant (no machine-to-machine OAuth)
- We do not implement refresh token rotation for now (can add later)
- We do not support `token_endpoint_auth_method: private_key_jwt` (only `none` and `client_secret_post`)
