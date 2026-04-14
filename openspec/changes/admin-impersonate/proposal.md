## Why

Customer support and debugging require staff to reproduce issues in a customer's environment. Currently there is no way for Uptrack staff to view or act as a specific user without direct database access, which is slow, error-prone, and unauditable. Admin impersonation gives authorized staff a secure, fully logged mechanism to operate as any user for up to one hour.

## What Changes

- Add `is_admin` boolean column to the `app.users` table via a new Ecto migration, defaulting to `false`.
- Introduce `POST /api/admin/impersonate` endpoint that starts an impersonation session (accepts `target_user_id`).
- Introduce `DELETE /api/admin/impersonate` endpoint that ends an active impersonation session.
- Create `ImpersonationPlug` that reads impersonation state from the session (`impersonating_user_id`, `impersonation_started_at`), swaps `current_user` to the target, and exposes `impersonating_admin` assign for the real staff user.
- Enforce a 1-hour hard timeout on impersonation sessions; expired sessions show a banner and redirect to `/admin`.
- Log every action performed during impersonation to the existing `app.audit_logs` table with both the admin's user ID and the target user ID in metadata.
- Frontend: admin UI panel to search organizations/users, start impersonation, and an "Exit Impersonation" overlay bar with manual exit button.

## Capabilities

### New Capabilities

- `admin-impersonation`: Session overlay model, ImpersonationPlug, start/stop endpoints, 1-hour timeout, admin gate (`is_admin` field), and impersonation-aware audit logging.
- `admin-ui`: Admin panel for searching orgs/users, initiating impersonation, and the impersonation banner/exit bar in the frontend.

### Modified Capabilities


## Impact

- **Database**: New migration adding `is_admin` boolean to `app.users`.
- **Auth pipeline**: `ImpersonationPlug` inserted after `ApiAuth` in the `:api_authenticated` pipeline; modifies `current_user` and adds `impersonating_admin` assign.
- **Audit logs**: All audit log entries created during impersonation will carry `impersonated_by` in metadata, linking to the admin's user ID.
- **Router**: New `/api/admin/impersonate` scope with admin-only authorization.
- **Frontend (uptrack-web)**: New admin panel route, impersonation banner component, TanStack Router guards for admin routes.
- **Security**: Impersonation restricted to `is_admin = true` users only; API key auth cannot initiate impersonation (session-only).
