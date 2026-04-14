## ADDED Requirements

### Requirement: Admin user and organization search endpoints

The system SHALL provide `GET /api/admin/users` and `GET /api/admin/organizations` endpoints for searching users and organizations. Both endpoints SHALL accept a `q` query parameter for text search and support pagination via `page` and `per_page` parameters.

#### Scenario: Search users by email
- **WHEN** an admin sends `GET /api/admin/users?q=john@example.com`
- **THEN** the system SHALL return a paginated list of users whose email matches the query (case-insensitive partial match)
- **THEN** each user result SHALL include `id`, `name`, `email`, `organization_id`, `organization_name`, `role`, and `is_admin`

#### Scenario: Search users by name
- **WHEN** an admin sends `GET /api/admin/users?q=John`
- **THEN** the system SHALL return a paginated list of users whose name matches the query (case-insensitive partial match)

#### Scenario: Search organizations by name
- **WHEN** an admin sends `GET /api/admin/organizations?q=Acme`
- **THEN** the system SHALL return a paginated list of organizations whose name matches the query
- **THEN** each result SHALL include `id`, `name`, `member_count`, and `plan`

#### Scenario: Empty search results
- **WHEN** an admin sends a search request with a query that matches no records
- **THEN** the system SHALL return HTTP 200 with an empty `data` array and pagination metadata

#### Scenario: Non-admin attempts search
- **WHEN** a non-admin user sends a request to `GET /api/admin/users` or `GET /api/admin/organizations`
- **THEN** the system SHALL return HTTP 403 Forbidden

### Requirement: Admin panel frontend route

The frontend SHALL provide an `/admin` route accessible only to users with `is_admin = true`. The admin panel SHALL display a search interface for finding users and organizations, and a button to start impersonation for any found user.

#### Scenario: Admin navigates to admin panel
- **WHEN** an admin user navigates to `/admin`
- **THEN** the frontend SHALL display the admin panel with user/organization search
- **THEN** the search results SHALL show user details and an "Impersonate" button for each user

#### Scenario: Non-admin navigates to admin panel
- **WHEN** a non-admin user navigates to `/admin`
- **THEN** the frontend SHALL redirect to the dashboard with no admin UI visible

#### Scenario: Admin initiates impersonation from panel
- **WHEN** an admin clicks "Impersonate" on a user row in the admin panel
- **THEN** the frontend SHALL call `POST /api/admin/impersonate` with the target user's ID
- **THEN** upon success, the frontend SHALL reload the auth state and redirect to the dashboard as the impersonated user

### Requirement: Impersonation banner display

The frontend SHALL display a persistent banner at the top of the viewport during an active impersonation session. The banner SHALL show the target user's name and email, the admin's name, a countdown timer to expiry, and an "Exit Impersonation" button.

#### Scenario: Banner shown during impersonation
- **WHEN** the frontend detects `impersonating_admin` in the `/api/auth/me` response
- **THEN** a fixed-position banner SHALL be displayed at the top of the page
- **THEN** the banner SHALL display "Impersonating {user_name} ({user_email}) as {admin_name}"
- **THEN** the banner SHALL display a countdown timer showing time remaining until the 1-hour expiry

#### Scenario: Banner not shown without impersonation
- **WHEN** the frontend detects no `impersonating_admin` in the `/api/auth/me` response
- **THEN** no impersonation banner SHALL be displayed

#### Scenario: Exit impersonation via banner button
- **WHEN** an admin clicks "Exit Impersonation" in the banner
- **THEN** the frontend SHALL call `DELETE /api/admin/impersonate`
- **THEN** upon success, the frontend SHALL reload auth state and redirect to `/admin`

#### Scenario: Impersonation expires during active session
- **WHEN** the frontend receives a 403 response with `{ "error": "impersonation_expired" }`
- **THEN** the frontend SHALL display an "Impersonation expired" notification
- **THEN** the frontend SHALL reload auth state and redirect to `/admin`

#### Scenario: Countdown timer reaches zero
- **WHEN** the client-side countdown timer reaches zero before a server response triggers expiry
- **THEN** the frontend SHALL proactively call `DELETE /api/admin/impersonate` and redirect to `/admin`
