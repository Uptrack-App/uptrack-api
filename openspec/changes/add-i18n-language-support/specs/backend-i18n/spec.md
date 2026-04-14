## ADDED Requirements

### Requirement: SetLocale plug applied to all request pipelines
A `UptrackWeb.Plugs.SetLocale` plug SHALL be inserted in the Phoenix `:browser` and `:api` pipelines after `:fetch_session`. It SHALL call `Gettext.put_locale(UptrackWeb.Gettext, locale)` and assign the resolved locale to `conn.assigns.locale` for every request.

#### Scenario: Locale set for authenticated API request
- **WHEN** an authenticated user with `preferred_locale = 'ja'` makes a `GET /api/monitors` request
- **THEN** `Gettext.get_locale()` within the request process returns `'ja'`

#### Scenario: Locale set for unauthenticated request via cookie
- **WHEN** a request arrives with no auth token and `Cookie: LOCALE=de`
- **THEN** `conn.assigns.locale` is `'de'`

---

### Requirement: Gettext translation files for all supported locales
The backend SHALL provide `.po` translation files under `priv/gettext/{locale}/LC_MESSAGES/` for each supported locale: `ja`, `de`, `es`, `pt_BR`. The `errors.po` domain SHALL cover all Ecto built-in validation error strings. The `default.po` domain SHALL cover all other user-facing backend strings.

#### Scenario: Ecto validation error translated
- **WHEN** a request with active locale `'ja'` triggers a required field validation error
- **THEN** the API response contains the Japanese translation of "can't be blank"

#### Scenario: Missing translation falls back to English
- **WHEN** a string has no entry in `ja/LC_MESSAGES/default.po`
- **THEN** the English msgid string is returned (Gettext built-in fallback)

---

### Requirement: Ecto validation errors translated at the view boundary only
Schema modules SHALL NOT call `gettext()` or `dgettext()`. Translation of Ecto changeset errors SHALL happen only in `UptrackWeb.ErrorHelpers.translate_error/1` (or equivalent JSON error view helper), which calls `Gettext.dgettext("errors", msg, opts)`.

#### Scenario: Validation error rendered in active locale
- **WHEN** a changeset error is rendered to JSON with active locale `'de'`
- **THEN** `translate_error/1` is called and returns the German error string
- **THEN** the JSON response body contains the German error message

#### Scenario: Schema module has no gettext calls
- **WHEN** the codebase is scanned
- **THEN** no call to `gettext/1`, `dgettext/2`, or `ngettext/3` appears in any Ecto schema or context module

---

### Requirement: Email notifications rendered in user's preferred locale
All transactional email functions SHALL accept a `locale` parameter and call `Gettext.put_locale(UptrackWeb.Gettext, locale)` before rendering. The caller (Oban worker or context function) SHALL read `user.preferred_locale` and pass it explicitly — not rely on the process-local Gettext locale from the HTTP request.

#### Scenario: Incident alert email sent in Japanese
- **WHEN** an alert is sent to a user with `preferred_locale = 'ja'`
- **THEN** the email subject and body are rendered in Japanese

#### Scenario: Email locale independent of request process
- **WHEN** an Oban `AlertDeliveryWorker` job renders an email
- **THEN** the email uses the locale from `user.preferred_locale` regardless of which HTTP request triggered the job

---

### Requirement: `pt-BR` locale aligned across backend and status pages
The `status_page_translations.ex` module SHALL use `'pt-BR'` (not `'pt'`) as the locale code for Brazilian Portuguese, consistent with the rest of the system. The `priv/gettext` directory SHALL use `pt_BR` (underscore, per GNU convention) as the folder name, mapping to BCP 47 `pt-BR` in locale resolution.

#### Scenario: pt-BR locale resolves to pt_BR gettext files
- **WHEN** the resolved locale is `'pt-BR'`
- **THEN** Gettext loads translations from `priv/gettext/pt_BR/LC_MESSAGES/`

#### Scenario: Status page serves Brazilian Portuguese
- **WHEN** a status page is requested with `Accept-Language: pt-BR`
- **THEN** the status page renders in Brazilian Portuguese using the `pt-BR` translation set
