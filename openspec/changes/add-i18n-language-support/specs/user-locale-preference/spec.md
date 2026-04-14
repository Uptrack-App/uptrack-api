## ADDED Requirements

### Requirement: User has a stored locale preference
The system SHALL store each user's preferred display language as a BCP 47 locale code in the `preferred_locale` column on the `app.users` table. The column SHALL default to `'en'` and SHALL accept the values: `en`, `ja`, `de`, `es`, `pt-BR`.

#### Scenario: Default locale for new users
- **WHEN** a new user account is created (via OAuth or password)
- **THEN** `preferred_locale` is set to `'en'`

#### Scenario: Locale persists across devices
- **WHEN** a user changes their language in Settings on one device
- **THEN** the same language is active when they sign in on a different device

---

### Requirement: Locale resolution priority chain
The system SHALL resolve the active locale per request using the following priority order: (1) authenticated user's `preferred_locale` from the database, (2) `LOCALE` cookie, (3) `Accept-Language` request header (first supported locale), (4) `'en'` as the hardcoded fallback. Unsupported locale codes SHALL be ignored and the next priority evaluated.

#### Scenario: Authenticated user locale takes precedence
- **WHEN** an authenticated user makes a request with `Accept-Language: de` but their `preferred_locale` is `'ja'`
- **THEN** the active locale is `'ja'`

#### Scenario: Cookie used for unauthenticated users
- **WHEN** an unauthenticated request is made with a valid `LOCALE=de` cookie
- **THEN** the active locale is `'de'`

#### Scenario: Accept-Language header auto-detection
- **WHEN** an unauthenticated request is made with no LOCALE cookie and `Accept-Language: ja,en;q=0.9`
- **THEN** the active locale is `'ja'`

#### Scenario: Unsupported locale falls through
- **WHEN** `Accept-Language` header contains only unsupported locales (e.g., `zh-TW`)
- **THEN** the active locale is `'en'`

---

### Requirement: User can change their language preference
The system SHALL allow an authenticated user to update their `preferred_locale` via the Account settings page. The language picker SHALL display language names in their own script (e.g., "日本語", "Deutsch", "Español", "Português (Brasil)"). The change SHALL take effect immediately on the next page render without requiring logout.

#### Scenario: Successful language change
- **WHEN** the user selects "日本語" in the language picker and saves
- **THEN** `preferred_locale` is updated to `'ja'` in the database
- **THEN** the UI re-renders in Japanese

#### Scenario: Language change via PATCH API
- **WHEN** `PATCH /api/users/me` is called with `{ "preferred_locale": "de" }`
- **THEN** the user's `preferred_locale` is updated to `'de'`
- **THEN** the response includes the updated user with `preferred_locale: "de"`

#### Scenario: Invalid locale rejected
- **WHEN** `PATCH /api/users/me` is called with `{ "preferred_locale": "xx" }` (unsupported code)
- **THEN** the API returns HTTP 422 with a validation error

---

### Requirement: Locale cookie set for unauthenticated visitors
The system SHALL set a `LOCALE` cookie (SameSite=Lax, Max-Age 1 year, Path=/) when a user selects a language before logging in. On signup or login, the system SHALL migrate the cookie locale to the new user's `preferred_locale` if the user has not yet set one.

#### Scenario: Cookie set on language selection pre-login
- **WHEN** an unauthenticated visitor selects "Deutsch" from the language picker
- **THEN** a `LOCALE=de` cookie is set in the browser
- **THEN** subsequent requests use `de` as the active locale

#### Scenario: Cookie locale migrated on signup
- **WHEN** a new user signs up with a `LOCALE=ja` cookie and no prior `preferred_locale`
- **THEN** their account is created with `preferred_locale = 'ja'`
