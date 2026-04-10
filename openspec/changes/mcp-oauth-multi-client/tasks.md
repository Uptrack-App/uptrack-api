# Tasks: MCP OAuth — Full Spec Compliance for All LLM Clients

## Phase 1 — Boruta DB + Discovery

- [ ] 1.1 Create consolidated Boruta migration at `priv/repo/migrations/*_create_boruta_tables.exs`
      — calls all 15 Boruta migration macros in order with `@prefix "app"`
- [ ] 1.2 Run migration on production (nbg1/nbg2 via colmena)
- [ ] 1.3 Verify tables exist: `clients`, `tokens`, `scopes`, `clients_scopes` in `app` schema
- [ ] 1.4 Deploy `WWW-Authenticate` header fix in `mcp_auth.ex` (already coded)
- [ ] 1.5 Add `registration_endpoint` and `client_id_metadata_document_supported: true`
      to `auth_server_metadata_controller.ex`
- [ ] 1.6 Verify `/.well-known/oauth-authorization-server` returns updated metadata

## Phase 2 — Consent UI (authorize flow)

- [ ] 2.1 Add `Uptrack.OAuth.resolve_client/1` in `oauth.ex` — takes `client_id`,
      returns `{:ok, %{name, redirect_uris}}` or `{:error, reason}`. Handles both
      plain string (Boruta lookup) and HTTPS URL (metadata doc fetch) via pattern matching.
- [ ] 2.2 Add `Uptrack.OAuth.fetch_client_metadata/1` — fetches Client ID Metadata Document
      from HTTPS URL. Validates: HTTPS scheme, not private IP, timeout 3s, `client_id`
      in doc matches URL exactly.
- [ ] 2.3 Rewrite `authorize_controller.ex` to:
      - Call `resolve_client/1` to get client name + allowed redirect_uris
      - If user not logged in → redirect to login with `return_to` param
      - If user logged in → show consent page (GET) or process approval (POST)
      - On approval → delegate to Boruta for auth code generation
- [ ] 2.4 Create consent page template `lib/uptrack_web/templates/oauth/authorize.html.heex`
      — shows app name, requested scopes, Allow/Deny buttons. Minimal styling (works in
      embedded webviews).
- [ ] 2.5 Wire login redirect: after magic link / Google / GitHub login during OAuth flow,
      return user to `/oauth/authorize` with original params intact (use session to store
      pending authorization).
- [ ] 2.6 Test full authorize flow manually with curl + browser

## Phase 3 — Dynamic Client Registration (RFC7591)

- [ ] 3.1 Create `lib/uptrack_web/controllers/oauth/registration_controller.ex`
      — handles `POST /oauth/register`
      - Accepts JSON body per RFC7591: `client_name`, `redirect_uris`, `grant_types`,
        `response_types`, `token_endpoint_auth_method`
      - Validates required fields, rejects non-HTTPS redirect URIs (except localhost)
      - Calls `Uptrack.OAuth.create_client/1` (Boruta Admin API) with `confidential: false`
      - Returns RFC7591 response: `client_id`, `client_secret` (if confidential),
        `client_id_issued_at`, `client_secret_expires_at`
- [ ] 3.2 Add rate limiting to registration endpoint: 10 requests/IP/hour via
      existing rate limit plug
- [ ] 3.3 Add `POST /oauth/register` to router (no auth required — public endpoint)
- [ ] 3.4 Test with curl: register a client, get back credentials, use them in authorize flow

## Phase 4 — Pre-registered Clients

- [ ] 4.1 Create Mix task `mix uptrack.oauth.seed_clients` that creates known LLM clients:
      - `claude-ai`: redirect `https://claude.ai/api/auth/oauth/callback`
      - `chatgpt`: redirect `https://chat.openai.com/aip/*/oauth/callback` (wildcard via
        Boruta if supported, else exact URI)
      Idempotent — skips if client already exists.
- [ ] 4.2 Run task on production
- [ ] 4.3 Output `client_id` and `client_secret` for each — document in internal notes

## Phase 5 — Validation

- [ ] 5.1 Claude.ai custom connector: enter Client ID/Secret → connect → verify tools work
- [ ] 5.2 Claude Desktop: API key still works (regression check)
- [ ] 5.3 Dynamic registration: `curl -X POST /oauth/register` → authorize → token → MCP call
- [ ] 5.4 Client ID Metadata Document: use URL client_id in authorize URL → verify fetch + consent
- [ ] 5.5 Verify `/.well-known/oauth-protected-resource` still correct
- [ ] 5.6 Verify `/.well-known/oauth-authorization-server` has `registration_endpoint` and
      `client_id_metadata_document_supported`
- [ ] 5.7 Verify 401 response includes `WWW-Authenticate: Bearer resource_metadata="..."`
