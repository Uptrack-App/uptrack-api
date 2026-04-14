## Context

Uptrack is a Phoenix API + TanStack Start/React frontend. The backend already has Gettext wired up (`uptrack_web/gettext.ex`) and a working multi-language status page translation module (`status_page_translations.ex` — supports en/de/fr/es/pt/ja/zh). The frontend has no i18n library; all strings are hardcoded in English. The `app.users` table has no locale field; timezone is stored in the `notification_preferences` JSONB map.

Target locales: `en` (base), `ja`, `de`, `es`, `pt-BR`.

## Goals / Non-Goals

**Goals:**
- Persist locale preference per authenticated user in the DB
- Resolve locale per request on the backend (for API error messages and emails)
- Instrument all frontend UI strings through Paraglide JS with compile-time type safety
- Settings UI to let users change their language
- Locale auto-detection on first visit (Accept-Language header → cookie)

**Non-Goals:**
- URL-prefixed routes for the authenticated app (e.g., `/ja/dashboard`) — no SEO benefit inside the app
- RTL layout support (Arabic, Hebrew) — significant CSS work, not in target markets
- Machine-translated content auto-published without review
- Marketing/blog page translation (separate concern, separate routing strategy)
- Per-organization default locale (future, if B2B multi-user teams need it)

## Decisions

### 1. Store locale in `app.users` column, not in `notification_preferences` JSONB

**Decision**: Add `preferred_locale varchar(10) DEFAULT 'en'` as a first-class column.

**Why not JSONB map**: `notification_preferences` is already a heterogeneous map for notification-specific settings. Locale is a cross-cutting concern used by the email renderer, the Gettext Plug, and the frontend — not just notifications. A dedicated column makes it queryable, indexable, and prevents silent JSONB key-miss bugs.

**Alternatives considered**: Adding `locale` key to the existing JSONB map (simpler migration, but wrong semantics and harder to query), or storing only in a browser cookie (doesn't survive browser/device changes).

---

### 2. Frontend: Paraglide JS over react-i18next

**Decision**: Use `@inlang/paraglide-js` with the Vite plugin.

**Why Paraglide**: Compile-time tree-shaking means only used message strings ship in the bundle (~1-2 KB runtime vs ~9 KB for react-i18next). Fully typed — accessing `m.nonexistent_key()` is a TypeScript compile error. TanStack Start has a documented Paraglide integration. Message files are plain JSON, readable by translators and compatible with all TMS tools (Crowdin, Weblate, Lokalise).

**Why not react-i18next**: Larger runtime, string-key lookups are not type-safe by default (requires declaration merging workaround), runtime parsing overhead.

**Why not Lingui**: Excellent library but requires a separate CLI extraction step and `.po` format on the frontend — mixing `.po` (backend) with `.po` (frontend) adds confusion about which files go to which renderer.

---

### 3. Locale resolution priority chain

**Decision** (in order of precedence):
1. `current_user.preferred_locale` (authenticated, highest trust)
2. `LOCALE` cookie (unauthenticated session persistence)
3. `Accept-Language` request header (first-visit auto-detection)
4. `"en"` hardcoded default

**Why**: This is the industry-standard chain. The cookie bridges the gap between first visit and login — if a user picks a language before signing up, the preference survives to signup and gets written to their DB record on creation.

**Where it runs**: A `UptrackWeb.Plugs.SetLocale` plug inserted after `:fetch_session` in both the `:browser` and `:api` pipelines. Sets `Gettext.put_locale/2` (per-process) and assigns `:locale` on the conn.

---

### 4. Backend email rendering: pass locale explicitly, don't rely on process dict

**Decision**: Pass `locale` as an explicit parameter to all email render functions, reading from `user.preferred_locale`.

**Why**: Oban workers run in separate processes; `Gettext.put_locale/2` is per-process. If we rely on `Gettext.get_locale()` inside an Oban job without re-setting it, emails render in English regardless of user locale. Explicit parameter passing is explicit, testable, and survives process boundary.

---

### 5. Ecto validation errors: translate at the view/controller boundary only

**Decision**: Schemas use plain English strings. `translate_error/1` helpers in `UptrackWeb.ErrorHelpers` call `Gettext.dgettext("errors", ...)` — locale is already set by the Plug when this runs.

**Why**: Schemas belong to the context layer, which must be web-framework-agnostic. Calling `gettext()` in schemas couples them to the web layer and breaks non-web callers (Oban workers, CLI mix tasks).

---

### 6. Date/number formatting: JS Intl API, no library

**Decision**: Use native `Intl.DateTimeFormat` and `Intl.NumberFormat` everywhere in the frontend. No external date/number formatting library.

**Why**: `Intl` is supported in all modern browsers and Node (used for SSR). Zero bundle cost. Sufficient for uptime percentages, response times, and timestamps.

## Risks / Trade-offs

**[String volume]** → Instrumenting all existing frontend strings is a large one-time effort. **Mitigation**: Do it in a focused batch pass, component by component, before adding any new features in that pass. Use ESLint to flag un-translated string literals post-migration.

**[Translation quality]** → Machine translation (DeepL) for initial launch may contain awkward phrasing. **Mitigation**: Japanese translation gets human review before launch (highest-priority market). German and Spanish can launch with DeepL + community feedback loop.

**[Paraglide compile-time strictness]** → Missing a message key is a compile error, which is good for safety but means we can't ship partially-translated builds. **Mitigation**: Use English fallback in Paraglide config — if a message key exists in `en.json` but not `ja.json`, fall back to English. Set `fallbackLanguage: "en"` in `project.inlang/settings.json`.

**[Gettext process isolation in LiveView]** → If Uptrack ever uses LiveView (currently it is a JSON API + SPA), locale must be re-applied in `mount/3`. Not an immediate risk but worth noting.

**[pt-BR vs pt]** → Brazilian Portuguese is `pt-BR` (BCP 47). The existing `status_page_translations.ex` uses `"pt"`. These must be kept consistent; the new system uses `pt-BR` (more specific, more correct for the target market).

## Migration Plan

1. **DB migration**: `ALTER TABLE app.users ADD COLUMN preferred_locale varchar(10) NOT NULL DEFAULT 'en'`. Zero downtime — column with default, no NOT NULL constraint violation on existing rows.
2. **Backend Plug**: Deploy `SetLocale` plug — purely additive, no behavior change for English users.
3. **Frontend Paraglide setup**: Install library, create `messages/en.json` with all existing strings, configure Vite plugin. App behavior unchanged (English only still).
4. **String instrumentation**: Replace hardcoded strings with `m.*()` calls across all frontend components. Deploy.
5. **Settings UI**: Language picker in Account settings. Users can now select a language but only English messages exist yet.
6. **Translations**: Add `ja.json`, `de.json`, `es.json`, `pt-BR.json`. Deploy incrementally — Paraglide falls back to English for any missing key.
7. **Email templates**: Update email render calls to pass `preferred_locale`. Add `.po` translations for email strings.

**Rollback**: Column default means rollback of any step leaves existing data intact. Removing the Paraglide plugin and reverting `vite.config.ts` restores the English-only frontend.

## Open Questions

- **Translation workflow**: ~~Decided~~ — use **DeepL API** directly. Generate translations programmatically from `messages/en.json` and `errors.pot`. No TMS needed. Add a script (`scripts/translate.ts` or `mix translate`) that calls DeepL and writes output files. Run it when new strings are added.
- **Language picker placement**: Settings page only, or also in the app header/profile dropdown? → Header placement is more discoverable but adds UI complexity.
- **`pt-BR` vs `pt`**: Align `status_page_translations.ex` to use `pt-BR` at the same time, or leave it as a separate cleanup? → Recommend aligning in this change to avoid divergence.
