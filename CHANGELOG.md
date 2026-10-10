# Changelog

Every feature commit adds a line under **Unreleased**. CI publishes that section as the notes of the `build-N` and `latest-build` releases. Once a build is out, its section is renamed to its version.

## Unreleased

### ✨ New
- **Where did this recipe come from?** Cards show a small badge on review and in the recipe: “Made with Apple Intelligence”, “Imported from page data” or “Demo”. Settings › About shows AI diagnostics (model status, plus the last run's source and speed). Older recipes are left as they were.
- **Tab bar** – Library, Shopping list (with a badge for items still to buy) and Settings, each keeping its place when you switch. It uses the iOS 26 Liquid Glass look. Cook mode and onboarding are full screen.
- **Save to ate** – share a link, a caption or a photo from Safari, TikTok, Instagram or Photos straight into ate.
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
- **Hands-free cook mode** – tap the mic and say “next”, “back”, “start timer”, “pause timer” or “repeat” (reads the step aloud). Recognition runs on your iPhone.

### 🐛 Fixed
- **Food photos work on the Image tab.** A photo of a dish (no text) no longer fails with “Couldn't read any text”. ate recognises the dish and drafts a likely recipe, badged “Guessed from photo”, for you to review and edit. The copy now explains screenshots versus photos.
- **Instagram, TikTok and YouTube links** no longer time out. ate reads the caption or description from the link preview (oEmbed/OpenGraph, ~8 s), strips tracking parameters, and builds the card from that. When Instagram hides the caption, ate says so and offers one tap to paste it into Prompt. Other pages now give up after 10 s with a clear message.
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
