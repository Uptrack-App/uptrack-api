## Why

Uptrack is English-only, which blocks adoption in high-value non-English markets (Japan, DACH, Latin America) where English proficiency is insufficient for enterprise purchasing decisions. Adding i18n infrastructure now — before user growth in these markets — avoids a costly retrofit later.

## What Changes

- Add `preferred_locale` column to `app.users` table (varchar(10), default `'en'`)
- Add locale resolution Plug to Phoenix pipeline (DB record → cookie → Accept-Language header → `"en"`)
- Install and configure Paraglide JS on the frontend (TanStack Start / Vite)
- Externalize all frontend UI strings to Paraglide JSON message files
- Add language picker to Settings > Account page and app header profile menu
- Translate all strings to: Japanese (`ja`), German (`de`), Spanish (`es`), Brazilian Portuguese (`pt-BR`)
- Render backend email notifications using the user's `preferred_locale`
- Translate Phoenix/Ecto validation error messages via Gettext per locale
- Format dates, times, and numbers using JS `Intl` API (locale-aware)
- Set `<html lang>` attribute dynamically from active locale

## Capabilities

### New Capabilities

- `user-locale-preference`: Store, resolve, and update a user's preferred display language, including the Settings UI to change it and the backend Plug to apply it per request.
- `frontend-i18n`: Paraglide JS setup, JSON message files for all UI strings, locale switching, and `Intl`-based date/number formatting.
- `backend-i18n`: Phoenix Gettext `.po` translation files, per-request locale in the Plug pipeline, translated Ecto validation errors, and locale-aware email rendering.

### Modified Capabilities

<!-- No existing specs have requirement changes from this change. -->

## Impact

**Database**: New migration adding `preferred_locale` to `app.users`.

**Backend**:
- New `Uptrack.Accounts.User` changeset field
- New `UptrackWeb.Plugs.SetLocale` plug inserted in browser + API pipelines
- `priv/gettext/` locale directories: `ja/`, `de/`, `es/`, `pt_BR/`
- Email templates in `uptrack-api/lib/uptrack_web/emails/` must accept and use locale
- `translate_error/1` helpers already present — just need `.po` files populated

**Frontend (`uptrack-web`)**:
- New dev dependency: `@inlang/paraglide-vite`, `@inlang/paraglide-js`
- New files: `project.inlang/`, `messages/en.json`, `messages/ja.json`, `messages/de.json`, `messages/es.json`, `messages/pt-BR.json`
- `vite.config.ts` updated with Paraglide plugin
- All hardcoded UI strings replaced with `m.*()` calls
- `__root.tsx` `lang` attribute set dynamically

**Settings UI**: New language selector in Account settings and profile dropdown.

**No breaking changes** to existing API contracts or data.
