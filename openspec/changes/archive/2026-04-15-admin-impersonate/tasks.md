## 1. Database Migration

- [x] 1.1 Create migration `priv/app_repo/migrations/<timestamp>_add_is_admin_to_users.exs` that adds `is_admin` boolean column to `app.users` table with default `false` and `null: false`
- [x] 1.2 Update `Uptrack.Accounts.User` schema in `lib/uptrack/accounts/user.ex`: add `field :is_admin, :boolean, default: false`. Do NOT add `:is_admin` to the general `changeset/2` cast list. Instead add an `admin_changeset/2` function (or set it via direct Ecto operations) to prevent privilege escalation through user-facing endpoints.
- [x] 1.3 Run `mix ecto.migrate` and verify the column exists

## 2. RequireAdminPlug

- [x] 2.1 Create `lib/uptrack_web/plugs/require_admin.ex` — `UptrackWeb.Plugs.RequireAdmin` plug that checks `conn.assigns.current_user.is_admin == true`, returns 403 `{ "error": "forbidden" }` otherwise
- [x] 2.2 Write tests in `test/uptrack_web/plugs/require_admin_test.exs` covering admin-allowed and non-admin-forbidden scenarios

## 3. ImpersonationPlug

- [x] 3.1 Create `lib/uptrack_web/plugs/impersonation.ex` — `UptrackWeb.Plugs.Impersonation` plug that:
  - Reads `impersonating_user_id` and `impersonation_started_at` from session
  - Only activates when `conn.assigns.auth_method == :session`
  - Loads target user via `Accounts.get_user!/1`, replaces `conn.assigns.current_user`
  - Sets `conn.assigns.impersonating_admin` to the original admin user
  - Reloads `conn.assigns.current_organization` from the target user's `organization_id`
  - On target user not found: clears session keys, proceeds with admin identity
- [x] 3.2 Add timeout check: if `impersonation_started_at` is older than 1 hour, clear session keys, log `admin.impersonation_expired` audit entry, return 403 `{ "error": "impersonation_expired" }`
- [x] 3.3 Write tests in `test/uptrack_web/plugs/impersonation_test.exs` covering: active impersonation swap, API key passthrough, no impersonation state passthrough, expired timeout, deleted target user

## 4. Router and Pipeline Updates

- [x] 4.1 Add `ImpersonationPlug` to the `:api_authenticated` pipeline in `lib/uptrack_web/router.ex`, positioned after `UptrackWeb.Plugs.ApiAuth`
- [x] 4.2 Create a new `:api_admin` pipeline in the router with: `:accepts ["json"]`, `:fetch_session`, `UptrackWeb.Plugs.ApiAuth`, `UptrackWeb.Plugs.RequireAdmin`, rate limit plug (lower limit, e.g., 30 req/min)
- [x] 4.3 Add new scope `"/api/admin"` using `:api_admin` pipeline with routes:
  - `post "/impersonate", AdminController, :start_impersonation`
  - `delete "/impersonate", AdminController, :stop_impersonation`
  - `get "/users", AdminController, :search_users`
  - `get "/organizations", AdminController, :search_organizations`

## 5. Admin Controller and Context

- [x] 5.1 Create `lib/uptrack_web/controllers/api/admin_controller.ex` — `UptrackWeb.Api.AdminController` with actions:
  - `start_impersonation/2`: validate `target_user_id` param, reject self-impersonation (422), reject target if `is_admin = true` (403, `cannot_impersonate_admin`), check for existing impersonation by reading session keys directly via `get_session(conn, :impersonating_user_id)` — do NOT rely on assigns since this pipeline has no ImpersonationPlug (409 if active), reject if `auth_method` is not `:session` (403), set session keys, create `admin.impersonation_started` audit log using target user's `organization_id`, return 200 with target user data
  - `stop_impersonation/2`: read real admin from `conn.assigns.current_user` (real identity since no ImpersonationPlug in this pipeline), clear session keys, create `admin.impersonation_ended` audit log, return 200 with admin's own user data
  - `search_users/2`: accept `q`, `page`, `per_page` params, query users with ILIKE on `name` and `email`, join organization for `organization_name`, return paginated results
  - `search_organizations/2`: accept `q`, `page`, `per_page` params, query organizations with ILIKE on `name`, include `member_count`, return paginated results
- [x] 5.2 Create `lib/uptrack_web/controllers/api/admin_json.ex` — `UptrackWeb.Api.AdminJSON` view with render functions for user search results, organization search results, impersonation responses
- [x] 5.3 Create `lib/uptrack/admin.ex` — `Uptrack.Admin` context module with functions:
  - `search_users(query_string, opts)` — Ecto query with ILIKE on `name`/`email`, pagination, joins organization
  - `search_organizations(query_string, opts)` — Ecto query with ILIKE on `name`, pagination, member count subquery
- [x] 5.4 Write tests in `test/uptrack_web/controllers/api/admin_controller_test.exs` covering all scenarios from the spec: start/stop impersonation, self-impersonation rejection, already-impersonating rejection, API key rejection, user/org search, non-admin 403

## 6. Audit Logging Integration

- [x] 6.1 Update `Uptrack.Teams.AuditLog` actions list in `lib/uptrack/teams/audit_log.ex` to include `admin.impersonation_started`, `admin.impersonation_ended`, `admin.impersonation_expired`
- [x] 6.2 Create `Teams.log_action_from_conn(conn, action, resource_type, resource_id, opts \\ [])` helper in `lib/uptrack/teams.ex`. This function extracts `user_id` and `organization_id` from `conn.assigns.current_user`, extracts `ip_address` from the conn, and automatically merges `impersonated_by: admin.id` into `metadata` when `conn.assigns.impersonating_admin` is present. This single call site handles all enrichment.
- [x] 6.3 Replace existing direct `Teams.log_action(...)` calls in controllers with `Teams.log_action_from_conn(conn, ...)`. Grep for `log_action` to find all call sites. Do NOT update context functions — only controller-level calls should change since only the conn (not context functions) has access to the impersonation assigns.
- [x] 6.4 Write tests verifying that audit logs created during impersonation contain `impersonated_by` in metadata and that logs created without impersonation do not

## 7. Auth Me Endpoint Update

- [x] 7.1 Update `UptrackWeb.Api.AuthController.me/2` in `lib/uptrack_web/controllers/api/auth_controller.ex` to check for `conn.assigns.impersonating_admin` and include `impersonating_admin` (id, name, email), `impersonation_started_at`, and `impersonation_expires_at` fields in the response when present
- [x] 7.2 Update the corresponding JSON view to render impersonation fields
- [x] 7.3 Write tests for `/api/auth/me` during impersonation and without impersonation

## 8. Frontend — Admin Panel (uptrack-web)

- [x] 8.1 Add `/admin` route in TanStack Router with an admin guard that checks `is_admin` from the auth state, redirecting non-admins to `/dashboard`
- [x] 8.2 Create `AdminPanel` page component with user/org search input, results table, and "Impersonate" button per user row
- [x] 8.3 Create API client functions for `POST /api/admin/impersonate`, `DELETE /api/admin/impersonate`, `GET /api/admin/users?q=`, `GET /api/admin/organizations?q=`
- [x] 8.4 On impersonate click: call start endpoint, invalidate auth query cache, redirect to `/dashboard`

## 9. Frontend — Impersonation Banner

- [x] 9.1 Create `ImpersonationBanner` component: fixed-position bar at top of viewport, displays target user name/email, admin name, countdown timer, "Exit Impersonation" button
- [x] 9.2 Integrate `ImpersonationBanner` into the root layout, conditionally rendered when `impersonating_admin` is present in auth state
- [x] 9.3 Implement countdown timer logic: compute remaining time from `impersonation_expires_at`, on reaching zero call `DELETE /api/admin/impersonate` and redirect to `/admin`
- [x] 9.4 Handle 403 `impersonation_expired` error globally in the API client (e.g., Axios/fetch interceptor): show "Impersonation expired" toast, invalidate auth cache, redirect to `/admin`

## 10. Manual Verification

- [x] 10.1 Set `is_admin = true` on a test user via psql, verify admin endpoints return 200 and non-admin gets 403
- [x] 10.2 Start impersonation, verify `/api/auth/me` returns impersonated user with admin metadata
- [x] 10.3 Perform an auditable action (e.g., create a monitor) during impersonation, verify audit log contains `impersonated_by` in metadata
- [x] 10.4 Wait for or simulate 1-hour timeout, verify 403 `impersonation_expired` response
- [x] 10.5 Verify "Exit Impersonation" returns admin to their own identity
