## Context

Uptrack is a multi-tenant uptime monitoring SaaS. Authentication is handled by `UptrackWeb.Plugs.ApiAuth` which supports Bearer token (API key) and session-based auth. The session stores `user_id`, and `current_user` is loaded from that. Users belong to exactly one organization and have a role within it (owner/admin/editor/viewer/notify_only). An `app.audit_logs` table already records significant actions with `user_id`, `organization_id`, `action`, `resource_type`, `resource_id`, and a `metadata` map.

There is currently no concept of a platform-level admin (staff). The `role` field on users is organization-scoped, not platform-scoped. There is no way for staff to view or act as a customer without direct database manipulation.

The frontend is a React + TanStack Router SPA on Cloudflare Pages, communicating with the Phoenix API over session cookies (same-origin) or Bearer tokens.

## Goals / Non-Goals

**Goals:**
- Allow designated staff users to temporarily act as any user in the system.
- Full audit trail: every action during impersonation records both the admin and the target user.
- Hard 1-hour timeout with automatic session cleanup.
- Clean UX: visible impersonation indicator, easy exit.

**Non-Goals:**
- Role-based admin permissions (e.g., read-only impersonation). All admins get full impersonation.
- Admin dashboard for system metrics, server health, or operational tooling beyond user/org search.
- Impersonation via API keys. Session-only to ensure browser-based audit trail.
- Nested impersonation (admin A impersonating admin B who impersonates user C).

## Decisions

### 1. Platform admin flag: `is_admin` boolean on users table

**Choice**: Add `is_admin` boolean column (default `false`) to `app.users`.

**Alternatives considered**:
- Separate `admins` table or role enum extension: Adds complexity for what is currently a simple on/off gate. A boolean is the simplest correct solution. Can be upgraded to a roles system later if needed.
- Environment variable allowlist of email addresses: Fragile, requires redeployment to change.

**Rationale**: A column on the users table is queryable, changeable at runtime, and requires no schema changes beyond a single migration. The `role` field is organization-scoped and should not be overloaded with platform concerns.

### 2. Session overlay model for impersonation state

**Choice**: Store impersonation state in the Phoenix session alongside the existing `user_id`:
- `session[:user_id]` remains the admin's ID (unchanged).
- `session[:impersonating_user_id]` is set to the target user's ID.
- `session[:impersonation_started_at]` is set to UTC datetime string.

`ImpersonationPlug` reads these, swaps `conn.assigns.current_user` to the target, and sets `conn.assigns.impersonating_admin` to the real admin user.

**Alternatives considered**:
- Separate impersonation token/JWT: More complex, requires token management, no real benefit over session for a browser-only feature.
- Database-backed impersonation sessions: Adds a table and queries per request. Session storage is sufficient since impersonation is inherently tied to a browser session.

**Rationale**: Session-based approach is simple, requires no new tables, and naturally expires when the session ends. The plug pattern fits Phoenix conventions and is easy to insert into the pipeline.

### 3. Plug placement: after ApiAuth in :api_authenticated pipeline

**Choice**: `ImpersonationPlug` runs after `ApiAuth` in the `:api_authenticated` pipeline. It only activates for session-based auth (not API key auth).

**Rationale**: `ApiAuth` sets `current_user` and `auth_method`. `ImpersonationPlug` needs both to decide whether to swap the user. Placing it after `ApiAuth` means it can check `auth_method == :session` and only activate for browser sessions.

### 4. Audit logging: metadata enrichment, not schema change

**Choice**: During impersonation, audit log entries include `impersonated_by: admin_user_id` in the existing `metadata` JSONB map. The `user_id` field on the audit log records the target user (the impersonated user), matching what the system "sees" as `current_user`.

**Alternatives considered**:
- Add `impersonated_by_id` column to `audit_logs`: Requires migration and changes to all audit log queries. The metadata map already exists for extensible data.

**Rationale**: Using metadata avoids schema changes and keeps the audit log write path simple. Queries for impersonated actions can filter on `metadata->>'impersonated_by' IS NOT NULL`.

### 5. Admin endpoints: new `/api/admin` scope

**Choice**: Create a new router scope `/api/admin` with its own pipeline that includes `ApiAuth` + `RequireAdminPlug`. Endpoints:
- `POST /api/admin/impersonate` — body: `{ "target_user_id": "<uuid>" }` — sets session impersonation state.
- `DELETE /api/admin/impersonate` — clears impersonation state from session.
- `GET /api/admin/users` — search users across all organizations (for the admin UI).
- `GET /api/admin/organizations` — search organizations (for the admin UI).

**Rationale**: Separate scope keeps admin routes cleanly isolated. `RequireAdminPlug` checks `current_user.is_admin == true` and returns 403 otherwise.

### 6. Timeout enforcement

**Choice**: `ImpersonationPlug` checks `impersonation_started_at` on every request. If more than 1 hour has elapsed, it clears the impersonation session keys and returns a JSON response with `{ "error": "impersonation_expired" }` and HTTP 403. The frontend detects this and shows an "Impersonation expired" banner, redirecting to `/admin`.

**Rationale**: Server-side enforcement ensures the timeout cannot be bypassed. The frontend also runs a timer for UX purposes (countdown in the banner), but the server is the authority.

### 7. Frontend approach

**Choice**: The `/api/auth/me` endpoint will be extended to return `impersonating_as` (target user) and `impersonating_admin` (admin user) fields when impersonation is active. The frontend uses this to:
- Show an impersonation banner bar at the top of the page.
- Display "Exit Impersonation" button that calls `DELETE /api/admin/impersonate`.
- Admin panel at `/admin` route with user/org search, accessible only when `is_admin` is true.

**Rationale**: Leveraging the existing `/api/auth/me` response avoids adding new polling endpoints. The banner is driven by auth state that's already fetched on app load.

## Risks / Trade-offs

- **[Risk] Admin account compromise grants access to all users** → Mitigation: `is_admin` is set manually in the database by operators, not through any UI. Impersonation is session-only (no API key). All impersonation actions are audit-logged. Consider adding 2FA requirement for admin actions in a future iteration.

- **[Risk] Session fixation during impersonation** → Mitigation: `POST /api/admin/impersonate` validates the target user exists and is not themselves an admin. The session ID itself does not change; only session data is modified. Standard CSRF protection applies.

- **[Risk] Stale impersonation state if user is deleted during impersonation** → Mitigation: `ImpersonationPlug` loads the target user on every request. If the user no longer exists, impersonation is automatically cleared and the admin is returned to their own identity.

- **[Trade-off] No granular admin permissions** → Acceptable for initial implementation. The `is_admin` boolean is a platform-level gate. Fine-grained admin roles (read-only, support-only) can be added later by replacing the boolean with a role/permission system.

- **[Trade-off] Session storage limits impersonation to one tab's context** → Acceptable. Impersonation is an active support tool, not a background process. If the admin opens multiple tabs, they all share the same session state, which is the desired behavior.

## Migration Plan

1. Deploy migration adding `is_admin` column (backward compatible, defaults to `false`).
2. Deploy backend code: `ImpersonationPlug`, `RequireAdminPlug`, admin controller, updated audit logging.
3. Manually set `is_admin = true` for staff users via `psql` or a mix task.
4. Deploy frontend: admin panel route, impersonation banner, exit button.
5. **Rollback**: Remove the plug from the pipeline and deploy. Session keys are harmless if the plug is absent. Migration is additive and does not need rollback.

## Resolved Decisions (added post-review)

- **Admin-impersonates-admin is blocked**: `POST /api/admin/impersonate` returns 403 `cannot_impersonate_admin` if the target user has `is_admin = true`. Rationale: prevents privilege confusion and lateral movement between admin accounts.
- **`is_admin` not in general `changeset/2`**: The field is NOT castable through user-facing registration or profile update endpoints. Only set via direct Ecto operations or a dedicated `admin_changeset/2`. Prevents privilege escalation through user-controlled input.
- **Audit log `organization_id` for impersonation events**: Use the target user's `organization_id` since the admin is operating in that org's context. Impersonation start/end/expire events are recorded against the org being accessed.
- **Admin controller reads session directly**: The `:api_admin` pipeline does NOT include `ImpersonationPlug`. The `AdminController` reads `get_session(conn, :impersonating_user_id)` directly to check impersonation state. `conn.assigns.current_user` in this pipeline is always the real admin.
- **Audit log enrichment via `Teams.log_action_from_conn/4`**: A new conn-aware helper centralises `impersonated_by` metadata injection. All controller-level audit log calls are migrated to this helper. Context-level calls are unchanged (no conn access there).

## Open Questions

- Should there be a notification to the target user that they were impersonated? Deferred to a future iteration.
