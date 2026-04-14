## ADDED Requirements

### Requirement: Platform admin flag on users

The system SHALL have an `is_admin` boolean field on the `app.users` table, defaulting to `false`. Only users with `is_admin = true` SHALL be permitted to access admin endpoints or initiate impersonation.

#### Scenario: Non-admin user attempts admin action
- **WHEN** a user with `is_admin = false` sends a request to any `/api/admin/*` endpoint
- **THEN** the system SHALL return HTTP 403 Forbidden with body `{ "error": "forbidden" }`

#### Scenario: Admin user accesses admin endpoint
- **WHEN** a user with `is_admin = true` sends an authenticated request to an `/api/admin/*` endpoint
- **THEN** the system SHALL process the request normally

### Requirement: Start impersonation session

The system SHALL provide a `POST /api/admin/impersonate` endpoint that accepts `{ "target_user_id": "<uuid>" }` and initiates an impersonation session. The endpoint SHALL only be accessible via session-based authentication (not API key). The endpoint SHALL store `impersonating_user_id` and `impersonation_started_at` in the Phoenix session.

#### Scenario: Admin starts impersonation of a valid user
- **WHEN** an admin user sends `POST /api/admin/impersonate` with a valid `target_user_id`
- **THEN** the system SHALL set `impersonating_user_id` and `impersonation_started_at` in the session
- **THEN** the system SHALL return HTTP 200 with the target user's profile data
- **THEN** the system SHALL create an audit log entry with action `admin.impersonation_started`

#### Scenario: Admin attempts to impersonate themselves
- **WHEN** an admin user sends `POST /api/admin/impersonate` with their own user ID as `target_user_id`
- **THEN** the system SHALL return HTTP 422 with body `{ "error": "cannot_impersonate_self" }`

#### Scenario: Admin attempts to impersonate another admin user
- **WHEN** an admin user sends `POST /api/admin/impersonate` with a `target_user_id` that belongs to a user with `is_admin = true`
- **THEN** the system SHALL return HTTP 403 with body `{ "error": "cannot_impersonate_admin" }`

#### Scenario: Admin attempts to impersonate a non-existent user
- **WHEN** an admin user sends `POST /api/admin/impersonate` with a `target_user_id` that does not exist
- **THEN** the system SHALL return HTTP 404 with body `{ "error": "user_not_found" }`

#### Scenario: Admin attempts to start impersonation while already impersonating
- **WHEN** an admin user sends `POST /api/admin/impersonate` while an impersonation session is already active
- **THEN** the system SHALL return HTTP 409 with body `{ "error": "already_impersonating" }`

#### Scenario: Non-session auth attempts impersonation
- **WHEN** a request to `POST /api/admin/impersonate` is authenticated via API key (Bearer token)
- **THEN** the system SHALL return HTTP 403 with body `{ "error": "session_auth_required" }`

### Requirement: End impersonation session

The system SHALL provide a `DELETE /api/admin/impersonate` endpoint that clears the impersonation state from the session and returns the admin to their own identity.

#### Scenario: Admin ends active impersonation
- **WHEN** an admin user sends `DELETE /api/admin/impersonate` while impersonating a target user
- **THEN** the system SHALL clear `impersonating_user_id` and `impersonation_started_at` from the session
- **THEN** the system SHALL return HTTP 200 with the admin's own profile data
- **THEN** the system SHALL create an audit log entry with action `admin.impersonation_ended`

#### Scenario: Admin attempts to end impersonation when not impersonating
- **WHEN** an admin user sends `DELETE /api/admin/impersonate` without an active impersonation session
- **THEN** the system SHALL return HTTP 200 with the admin's own profile data (no-op)

### Requirement: ImpersonationPlug swaps current user during impersonation

The system SHALL include an `ImpersonationPlug` in the `:api_authenticated` pipeline, positioned after `ApiAuth`. When impersonation session keys are present and the auth method is `:session`, the plug SHALL replace `conn.assigns.current_user` with the target user and set `conn.assigns.impersonating_admin` to the real admin user. When auth method is `:api_key`, the plug SHALL not modify any assigns.

#### Scenario: Request during active impersonation via session auth
- **WHEN** a session-authenticated request is made with valid impersonation state in the session
- **THEN** `conn.assigns.current_user` SHALL be the target (impersonated) user
- **THEN** `conn.assigns.impersonating_admin` SHALL be the admin user
- **THEN** `conn.assigns.current_organization` SHALL be the target user's organization

#### Scenario: Request via API key with impersonation session keys present
- **WHEN** an API key-authenticated request is made, even if the underlying session has impersonation keys
- **THEN** the plug SHALL NOT modify `current_user` or set `impersonating_admin`

#### Scenario: Request with no impersonation state
- **WHEN** a session-authenticated request is made without impersonation session keys
- **THEN** the plug SHALL NOT modify any assigns (pass-through)

#### Scenario: Target user no longer exists during impersonation
- **WHEN** a request is made during impersonation but the target user has been deleted
- **THEN** the plug SHALL clear the impersonation session keys
- **THEN** the plug SHALL proceed with the admin's own identity (no error)

### Requirement: Impersonation hard timeout of 1 hour

The system SHALL enforce a maximum impersonation duration of 1 hour. The `ImpersonationPlug` SHALL check `impersonation_started_at` on every request and automatically expire sessions that exceed 1 hour.

#### Scenario: Impersonation session within timeout
- **WHEN** a request is made during impersonation and `impersonation_started_at` is less than 1 hour ago
- **THEN** the plug SHALL proceed normally with the impersonated identity

#### Scenario: Impersonation session exceeds timeout
- **WHEN** a request is made during impersonation and `impersonation_started_at` is more than 1 hour ago
- **THEN** the plug SHALL clear the impersonation session keys
- **THEN** the system SHALL return HTTP 403 with body `{ "error": "impersonation_expired" }`
- **THEN** the system SHALL create an audit log entry with action `admin.impersonation_expired`

### Requirement: Audit logging during impersonation

Every action logged to `app.audit_logs` during an active impersonation session SHALL include the admin's user ID in the `metadata` map under the key `impersonated_by`. The `user_id` field on the audit log SHALL be set to the target (impersonated) user's ID.

#### Scenario: Action performed during impersonation
- **WHEN** any auditable action occurs while impersonation is active
- **THEN** the audit log entry's `user_id` SHALL be the target user's ID
- **THEN** the audit log entry's `metadata` SHALL contain `"impersonated_by": "<admin_user_id>"`

#### Scenario: Action performed without impersonation
- **WHEN** any auditable action occurs without an active impersonation session
- **THEN** the audit log entry SHALL NOT contain `impersonated_by` in metadata

### Requirement: Auth me endpoint reflects impersonation state

The `GET /api/auth/me` endpoint SHALL include impersonation information when an impersonation session is active.

#### Scenario: Auth me during impersonation
- **WHEN** `GET /api/auth/me` is called during an active impersonation session
- **THEN** the response SHALL include the target user's data as the primary user
- **THEN** the response SHALL include an `impersonating_admin` object with the admin user's `id`, `name`, and `email`
- **THEN** the response SHALL include `impersonation_started_at` and `impersonation_expires_at` timestamps

#### Scenario: Auth me without impersonation
- **WHEN** `GET /api/auth/me` is called without an active impersonation session
- **THEN** the response SHALL NOT include `impersonating_admin` or impersonation timestamps

### Requirement: Nested impersonation prevention

The system SHALL prevent an admin who is currently impersonating a user from initiating another impersonation. Admin endpoints related to impersonation SHALL operate on the real admin identity, not the impersonated identity.

#### Scenario: Impersonating admin attempts to impersonate another user
- **WHEN** an admin is impersonating user A and sends `POST /api/admin/impersonate` with user B's ID
- **THEN** the system SHALL return HTTP 409 with body `{ "error": "already_impersonating" }`
