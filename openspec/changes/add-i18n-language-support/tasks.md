## 1. Database & User Model

- [ ] 1.1 Write Ecto migration: add `preferred_locale varchar(10) NOT NULL DEFAULT 'en'` to `app.users`
- [ ] 1.2 Add `preferred_locale` field to `Uptrack.Accounts.User` schema and changeset with validation (inclusion in supported locales)
- [ ] 1.3 Add `update_locale/2` function in `Uptrack.Accounts` context
- [ ] 1.4 Expose `PATCH /api/users/me` endpoint to update `preferred_locale` (or extend existing user update endpoint)

## 2. Backend Locale Plug

- [ ] 2.1 Create `UptrackWeb.Plugs.SetLocale` — resolves locale via priority chain (user DB → cookie → Accept-Language → `"en"`)
- [ ] 2.2 Insert `SetLocale` plug into the `:browser` pipeline in `router.ex` (after `:fetch_session`)
- [ ] 2.3 Insert `SetLocale` plug into the `:api` pipeline in `router.ex`
- [ ] 2.4 Write unit tests for `SetLocale` covering all four priority cases and unsupported-locale fallthrough

## 3. Backend Gettext Translations

- [ ] 3.1 Run `mix gettext.extract` to generate/update `.pot` files from existing code
- [ ] 3.2 Run `mix gettext.merge priv/gettext --locale ja` (and `de`, `es`, `pt_BR`) to scaffold `.po` files
- [ ] 3.3 Translate `errors.po` for `ja` (all built-in Ecto validation strings)
- [ ] 3.4 Translate `errors.po` for `de`, `es`, `pt_BR`
- [ ] 3.5 Translate `default.po` for `ja` (all non-error backend strings)
- [ ] 3.6 Translate `default.po` for `de`, `es`, `pt_BR`
- [ ] 3.7 Fix `status_page_translations.ex` to use `pt-BR` instead of `pt` for Brazilian Portuguese

## 4. Email Locale Support

- [ ] 4.1 Audit all email render functions in `uptrack-api/lib/uptrack_web/emails/` — list those missing a `locale` parameter
- [ ] 4.2 Add `locale` parameter to each email render function; call `Gettext.put_locale/2` before rendering
- [ ] 4.3 Update all callers (Oban workers, context functions) to pass `user.preferred_locale`
- [ ] 4.4 Add translated subject lines and body strings to `default.po` for each locale

## 5. Frontend: Paraglide Setup

- [ ] 5.1 Install `@inlang/paraglide-js` and `@inlang/paraglide-vite` via pnpm
- [ ] 5.2 Create `project.inlang/settings.json` with supported locales (`en`, `ja`, `de`, `es`, `pt-BR`) and `fallbackLanguage: "en"`
- [ ] 5.3 Add Paraglide Vite plugin to `vite.config.ts`
- [ ] 5.4 Create `messages/en.json` as the base message file (initially empty — populated in step 6)
- [ ] 5.5 Create `messages/ja.json`, `messages/de.json`, `messages/es.json`, `messages/pt-BR.json` (initially `{}`)
- [ ] 5.6 Verify Paraglide compiles and TypeScript types are generated at `src/paraglide/`

## 6. Frontend: String Instrumentation

- [ ] 6.1 Instrument strings in auth routes (login, signup, forgot password)
- [ ] 6.2 Instrument strings in dashboard / monitors list
- [ ] 6.3 Instrument strings in monitor detail and edit forms
- [ ] 6.4 Instrument strings in incidents and alerts views
- [ ] 6.5 Instrument strings in status page editor UI
- [ ] 6.6 Instrument strings in billing / subscription pages
- [ ] 6.7 Instrument strings in settings pages
- [ ] 6.8 Instrument strings in shared components (navigation, modals, toasts, empty states, error boundaries)
- [ ] 6.9 Replace all hardcoded date/time formatting with `Intl.DateTimeFormat` using active locale
- [ ] 6.10 Replace all hardcoded number/percentage formatting with `Intl.NumberFormat` using active locale

## 7. Frontend: Locale Initialization & Switching

- [ ] 7.1 On app load, call `setLocale(user.preferred_locale)` after the user record is fetched
- [ ] 7.2 Set `<html lang={getLocale()}>` dynamically in `__root.tsx`
- [ ] 7.3 For unauthenticated pages: read `LOCALE` cookie on init and call `setLocale()` accordingly
- [ ] 7.4 When `PATCH /api/users/me` succeeds (locale change), call `setLocale(newLocale)` in the frontend

## 8. Settings UI: Language Picker

- [ ] 8.1 Add language selector component to Settings > Account page (globe icon + language name in native script)
- [ ] 8.2 Wire selector to `PATCH /api/users/me` with optimistic locale update
- [ ] 8.3 Add language selector to profile/avatar dropdown in the app header (for discoverability)
- [ ] 8.4 For unauthenticated pages (marketing, login): add language picker in footer that sets the `LOCALE` cookie

## 9. DeepL Translation Script

- [ ] 9.1 Create `uptrack-web/scripts/translate.ts` — reads `messages/en.json`, calls DeepL API for each target locale (`ja`, `de`, `es`, `pt-BR`), writes output files (skip keys already translated)
- [ ] 9.2 Create `uptrack-api/scripts/translate_po.exs` (or Mix task) — calls DeepL for each untranslated `msgid` in `.pot` files, writes `.po` files for `ja`, `de`, `es`, `pt_BR`
- [ ] 9.3 Add `DEEPL_API_KEY` to agenix secrets and runtime config
- [ ] 9.4 Run frontend translation script — generate all four `messages/*.json` files
- [ ] 9.5 Run backend translation script — generate all four locale `.po` files
- [ ] 9.6 Verify Japanese rendering in UI (font, text overflow, date/number formats)
- [ ] 9.7 Spot-check German, Spanish, Brazilian Portuguese in the UI for obvious errors or layout breakage
