# Changelog

Every feature commit adds a line under **Unreleased**. CI publishes that section as the notes of the `build-N` and `latest-build` releases. Once a build is out, its section is renamed to its version.

## Unreleased

#### ⌚ Apple Watch app (new, independent)
- watchOS 11+ app that works without the iPhone: recipes synced from your ate account (email-code sign-in on the wrist, or automatic hand-off from the paired iPhone), offline cache, ingredients, wrist Cook mode (big step text, Next/Back + Digital Crown, step timers that keep running with haptics), Smart Stack timer widget, and shopping list tick-off. Mirrors the phone's active cook timers. Embedded in the `.ipa`; see README for free-Apple-ID install limits.

#### 🔎 Live Activity diagnostics
- More › About › Live Activity shows `areActivitiesEnabled`, the last request result or error, active count, bundle IDs and the PlugIns actually installed. Request errors are no longer swallowed (`try?`) and are logged; requests are skipped (and reported) when the app is in the background. README/SUPPORT document Sideloadly's *Remove extensions* option.

#### 🐛 Fixed
- **The app now rotates.** `Info.plist` only allowed portrait, so the landscape sidebar and two-column grid never appeared on a real iPhone. Portrait, landscape left and landscape right are now supported, and the grid fits two columns beside the sidebar on iPhone 17.
- Recipe detail hides the tab bar so the Cook mode button is no longer covered; the shopping list's last rows clear the tab bar.

## ✨ New
- **Cleaner tab bar.** Exactly four tabs with short labels: Library, Shopping (with badge), More and Settings. Collections no longer leak into the bar or the system "More" list. Selected tab is brand orange, others secondary grey.
- **New More screen** in ate's own styling: Collections (Quick, Favourites, Recently added, Recently cooked), By ingredient, Tools (export/import, replay intro, Privacy/Terms) and About (version, AI transparency, what to expect in beta, AI diagnostics). Settings now holds only Account & sync, Private mode, Units, Timer notifications and Your data.
- **Quick ≤30 min** is now the first filter chip in the Library.
- **Group & sort your library.** Group by Recently added (Today/This week/Earlier), Cuisine (filled in by the AI, editable), Main ingredient or Cook time. Sort by Newest, A–Z, Quickest, Recently cooked, Favourites first or **My order**, where you drag cards to arrange them (synced). Your choice is remembered.
- **Swipe and long-press.** Swipe left to delete (with Undo), swipe right to Favourite or add to the shopping list. Long-press any card for Cook, Share, Favourite, Add to list and Delete, with a rounded preview.
- **Landscape sidebar and recipe grid.** Turn your iPhone sideways for a collapsible sidebar (Library, Shopping list, Settings and Collections) and a grid of recipe cards with thumbnails. Portrait is unchanged. It uses the adaptable `TabView` sidebar, ready for iPad.
- **Collections:** Quick (under 30 min), Favourites (★ on any recipe), Recently added, Recently cooked, and automatic collections by main ingredient (Chicken, Fish, Pasta…).
- **Filter chips** under search: time (≤15/30/60 min), how the recipe was added (link, photo, prompt, shared), servings, Favourites and ingredient tags (chicken, beef, vegetarian, pasta…). They're multi-select, show a result count and a Clear button, and are remembered between launches.
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

- **QA release gate.** A dedicated `KeyFlowsQATests` suite covers the 8 key flows; CI only publishes a build when all pass, and the release notes carry the QA table and the MVP checklist score.
- **MVP checklist** (`docs/MVP_CHECKLIST.md`) with an honest status per item, plus `docs/BETA.md` and an in-app “What to expect in this beta” note in Settings › About.
- **AI transparency** line in onboarding and Settings.
- **Session expiry** is explained clearly: you're signed out on this iPhone, your recipes stay, sign in again to keep syncing.
- **Safer account switching:** signing in as a different account no longer mixes the previous account's recipes into it.

### 🐛 Fixed
- Repeat syncs could re-upload the same recipes forever (fractional timestamps vs whole-millisecond server stamps). Sync is now idempotent.
- Settings › Your data no longer says recipes are “on this device only” when you're signed in and syncing.
- **Food photos work on the Image tab.** A photo of a dish (no text) no longer fails with “Couldn't read any text”. ate recognises the dish and drafts a likely recipe, badged “Guessed from photo”, for you to review and edit. The copy now explains screenshots versus photos.
- **Instagram, TikTok and YouTube links** no longer time out. ate reads the caption or description from the link preview (oEmbed/OpenGraph, ~8 s), strips tracking parameters, and builds the card from that. When Instagram hides the caption, ate says so and offers one tap to paste it into Prompt. Other pages now give up after 10 s with a clear message.
- Recipe pages that block the default downloader now load (browser user agent).

### 🗺️ Planned (v1.3 hardening, see the PRD)
- Release blockers: universal links (paid account, ate.app, AASA) and a production security review (RLS, edge-function auth, retention, service-role key).
- Docs match real behaviour, config is separated from secrets, real-device auth and sync testing, the Apple Intelligence fallback checked on every device class, end-to-end tests against a staging Supabase, and modularisation with contract tests.

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
