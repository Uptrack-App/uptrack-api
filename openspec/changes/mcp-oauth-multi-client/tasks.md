# Tasks: MCP OAuth — Full Spec Compliance for All LLM Clients

## Phase 1 — Boruta DB + Discovery

- [x] 1.1 Create consolidated Boruta migration at `priv/repo/migrations/*_create_boruta_tables.exs`
      — calls all 15 Boruta migration macros in order with `@prefix "app"`
- [x] 1.2 Run migration on production (nbg1/nbg2 via colmena)
- [x] 1.3 Verify tables exist: `clients`, `tokens`, `scopes`, `clients_scopes` in `app` schema
- [x] 1.4 Deploy `WWW-Authenticate` header fix in `mcp_auth.ex` (already coded)
- [x] 1.5 Add `registration_endpoint` and `client_id_metadata_document_supported: true`
      to `auth_server_metadata_controller.ex`
- [x] 1.6 Verify `/.well-known/oauth-authorization-server` returns updated metadata

## Phase 2 — Consent UI (authorize flow)

- [x] 2.1 Add `Uptrack.OAuth.resolve_client/1` in `oauth.ex` — takes `client_id`,
      returns `{:ok, %{name, redirect_uris}}` or `{:error, reason}`. Handles both
      plain string (Boruta lookup) and HTTPS URL (metadata doc fetch) via pattern matching.
- [x] 2.2 Add `Uptrack.OAuth.fetch_client_metadata/1` — fetches Client ID Metadata Document
      from HTTPS URL. Validates: HTTPS scheme, not private IP, timeout 3s, `client_id`
      in doc matches URL exactly.
- [x] 2.3 Rewrite `authorize_controller.ex` to:
      - Call `resolve_client/1` to get client name + allowed redirect_uris
      - If user not logged in → redirect to login with `return_to` param
      - If user logged in → show consent page (GET) or process approval (POST)
      - On approval → delegate to Boruta for auth code generation
- [x] 2.4 Create consent page template `lib/uptrack_web/controllers/oauth/authorize_html/authorize.html.heex`
      — shows app name, requested scopes, Allow/Deny buttons. Minimal styling (works in
      embedded webviews).
- [x] 2.5 Wire login redirect: after magic link / Google / GitHub login during OAuth flow,
      return user to `/oauth/authorize` with original params intact (use session to store
      pending authorization).
- [x] 2.6 Test full authorize flow manually with curl + browser
      — login page renders correctly (single layout), client_name resolved from Boruta,
        dynamic registered client works, login redirect via pending_oauth_params session verified

## Phase 3 — Dynamic Client Registration (RFC7591)

- [x] 3.1 Create `lib/uptrack_web/controllers/oauth/registration_controller.ex`
      — handles `POST /oauth/register`
      - Accepts JSON body per RFC7591: `client_name`, `redirect_uris`, `grant_types`,
        `response_types`, `token_endpoint_auth_method`
      - Validates required fields, rejects non-HTTPS redirect URIs (except localhost)
      - Calls `Uptrack.OAuth.create_dynamic_client/1` (Boruta Admin API) with `confidential: false`
      - Returns RFC7591 response: `client_id`, `client_id_issued_at`
- [x] 3.2 Add rate limiting to registration endpoint: 10 requests/IP/hour via
      existing rate limit plug
- [x] 3.3 Add `POST /oauth/register` to router (no auth required — public endpoint)
- [x] 3.4 Test with curl: register a client, get back credentials, use them in authorize flow

## Phase 4 — Pre-registered Clients

- [x] 4.1 Create Mix task `mix uptrack.oauth.seed_clients` that creates known LLM clients:
      - `claude-ai`: redirect `https://claude.ai/api/auth/oauth/callback`
      - `chatgpt`: redirect `https://chat.openai.com/aip/plugin-b3b788fe-61c6-45c2-bb22-1b5d7fc2f2db/oauth/callback`
      Idempotent — skips if client already exists.
- [x] 4.2 Run task on production
- [x] 4.3 Output `client_id` and `client_secret` for each — document in internal notes
      - claude-ai: client_id=9a70dfdf-ad3a-478b-8a26-e4b7886468fd, client_secret=csupt-prod-ae810340-71fe-403d-886c-198cc3c114d8
      - chatgpt:   client_id=069b9028-2204-470c-befd-818e574cd738, client_secret=csupt-prod-20e98d0f-25c0-4c8d-b270-ae0fe0e6abee

## Phase 5 — Validation

- [ ] 5.1 Claude.ai custom connector: enter Client ID/Secret → connect → verify tools work
- [ ] 5.2 Claude Desktop: API key still works (regression check)
- [ ] 5.3 Dynamic registration: `curl -X POST /oauth/register` → authorize → token → MCP call
- [ ] 5.4 Client ID Metadata Document: use URL client_id in authorize URL → verify fetch + consent
- [x] 5.5 Verify `/.well-known/oauth-protected-resource` still correct
- [x] 5.6 Verify `/.well-known/oauth-authorization-server` has `registration_endpoint` and
      `client_id_metadata_document_supported`
- [x] 5.7 Verify 401 response includes `WWW-Authenticate: Bearer resource_metadata="..."`
