# Changelog

Every feature commit adds a line under **Unreleased**. CI publishes that section as the notes of the `build-N` and `latest-build` releases. Once a build is out, its section is renamed to its version.

## Unreleased

### ✨ New
- **Recipe links import instantly** – schema.org/JSON-LD data on recipe sites is read directly (exact ingredients, steps, times, servings, photo) before any AI is used.

- **Privacy Policy & Terms of Use published** – linked from onboarding, sign-in and Settings.
- **Real ate logo** – new app icon (light & dark), launch screen and in-app logo from the web app.
- **Timer chime** – a bundled 3-tone chime (also used for timer notifications) with matching haptic taps.
- **Take a photo** – snap a recipe with the camera on the Image tab.
- **Shopping list by aisle** – Produce, Bakery, Meat & Fish, Dairy, Pantry, Frozen, Other (toggle), with long-press actions.
- **Library gestures** – swipe left to delete, swipe right to cook, long-press menu, pull down to sync.
- **Offline & retry** – an offline banner, and failed imports or shared links show the reason with Try again.
- **Accessibility** – text follows your Dynamic Type size, more VoiceOver labels, stronger orange for contrast.
- Localization scaffolding (String Catalog).

### 🐛 Fixed
- Recipe pages that block the default downloader now load (browser user agent).

### ⚠️ Known issues
- Unsigned: install with Sideloadly/AltStore (free Apple ID: expires after 7 days, needs Developer Mode).
- Confirmation/reset emails are rate-limited (Supabase built-in mailer).
- The Lovable web page still reads the old backend, so new iOS shares won't load on the web.

## 0.1.14 (build 14)

### ✨ New
- Onboarding, sign-in screen (forgot password, magic link, confirm-email state), sign out (keep/remove local data), Delete account, build identity footer, privacy/terms links.

### 🐛 Fixed
- Sync failed (HTTP 400): integer timestamps and consistent row keys; server error shown in sync status.
- "The network connection was lost" on sign-in: HTTP/3 off, timeouts, automatic retry; friendlier auth errors.
