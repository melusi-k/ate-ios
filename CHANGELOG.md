# Changelog

Every feature commit adds a line under **Unreleased**. CI publishes that section as the notes of the `build-N` and `latest-build` releases. Once a build is out, its section is renamed to its version.

## Unreleased

### 🛟 Data safety (A-DATA-01/02)
- **Corrupt library recovery:** if the on-device store can't be opened, Ate moves it to `Backups/ate-<timestamp>.store`, opens a fresh store (in-memory as a last resort, never a crash), restores from sync when you're signed in, writes a JSON export of the recovered recipes, and shows a "Library repaired" screen with Export.
- **Save failures:** every SwiftData save retries twice, logs the error and shows a non-blocking banner; what's on screen is kept. Tests use a corrupt-store fixture and an injected save failure.

### 🔐 Supabase security review (A-SEC-01…06)
- `docs/SECURITY_REVIEW.md`: RLS, anon and other-user tokens, Edge Function auth and validation, rate limits, CORS, secrets inventory, storage, auth settings and the leaked-password check, with findings and a sign-off checklist.
- backend-e2e now runs these checks on every build. Hardening migration `20261011090000_security_hardening.sql` (revoke anon grants, fixed search_path, explicit share write lock, note length) is ready to apply.

### 📦 Release integrity (A-CI-05/06)
- Each IPA ships with a `.sha256` asset, and its SHA-256 is in the notes. A smoke step downloads the published asset, verifies the checksum, version and build, bundle ID, widgets and watch app, entitlements, privacy manifest, app icon and size limits, and withdraws the release if anything fails.
- One source of truth for docs: README, BETA, MVP_CHECKLIST and QA_MATRIX are reconciled (SideStore-first install, current build). `scripts/check-ids.py` fails CI when IDs drift between the checklist, the QA matrix and the in-app Beta checks, or when a service key shows up in client code.

### 📱 iOS 26 tab bar (build after 96; iOS 18–25 keep the previous UI)
- **Bottom accessory:** "Add recipe" now sits above the tab bar on every tab and replaces the floating button. When a timer is running, it shows the timer summary plus a + button, and the in-app timer bar no longer repeats on tab roots. It switches to a compact layout when the tab bar is minimised.
- **Tab bar** minimises when you scroll down.
- **Search tab:** Library search lives in the tab bar (Tab(role: .search)) next to the 4 main tabs, and "Your Kitchen" stays visible while searching.
- **Soft scroll edges** under the nav bar on Library, Shopping, More and Settings.
- **Sheet cards** in Add and Review follow the sheet's corner curve (ConcentricRectangle).
- **Recipe detail** hides the tab bar, so Cook mode and its bottom area never clash with the accessory.
- **Checks and tests:** new Beta checks C-TAB-01…06, QA matrix rows, a new UI test, and updated search and key-flow tests.

### 🛠 Tier C build 81 feedback (one build)
- **Step times:** plausibility minimums by verb (braise/stew/oxtail ≥ 60 min, simmer ≥ 20, pap ≥ 15, roast/bake ≥ 15, rice ≥ 12, brown/sear ≥ 5, steam ≥ 3). An implausible AI time with no time in the text is dropped (no "(N min)", no timer) and the card is flagged. The sanitizer now also runs on sync, edits and imports, not just on launch, and repaired recipes are saved and synced.
- **Empty steps:** blank steps are removed on decode, normalise, scaling, display and cook mode, and saved data is cleaned.
- **Offline strip:** moved inside each navigation stack, so it sits below the nav bar and never covers the title.
- **Siri/Shortcuts covers:** remote covers are downloaded into the shared cache before the card shows. If a recipe still has no image, the designed tile is used instead of the fork-and-knife icon.
- **Spotlight:** "Cook …" suggestions are capped at 3 (favourites first) and use real cover thumbnails. Indexed recipes carry thumbnails too.
- **Shortcuts "What's on my shopping list"** now returns the items as text, so it works with Show When Run off.
- **Siri diagnostics:** shows the bundle ID (re-signed or not), Siri language and voice-name count. Phrases are re-registered on every launch.
- **Duplicate saves (P0):** saves are idempotent by draft ID, the stored draft is cleared on save, Save is disabled while saving, an already-saved draft is never restored, and sync dedupes. A one-time merge combines exact duplicates created within 15 minutes of each other.
- **80% confidence:** dish identification happens inside the same generation pass. At 80% or above there's no question. Below 80%, Ate asks "What dish is this?" pre-filled with its guesses, then regenerates with the name you confirm. If it's still unsure, it shows "Draft, needs your input" and Save stays disabled until you edit or confirm.
- **Recipe quality bar:** a main dish needs at least 4 ingredients with amounts, oven steps need a °C temperature, there are no vague steps like "cook ribs", and times must be plausible.
- **Foundation Models:** nested @Generable output (DishIdentification → ingredients → steps with minutes and temperatureC) with guide constraints, a South African cook persona with rules and two example recipes, a streamed live preview, prewarm when the Add sheet opens, a clear message for each GenerationError, and Ask Ate revises the card in the same session.
- **Code-along 205 patterns:** prompts are built with Instructions { } and Prompt { }, with conditional lines for diet, servings and region. A one-shot GenRecipe.exampleMogodu goes in the prompt ("Here is an example of the desired format, but don't copy its content"). The schema is left out of the prompt by default; to A/B it, launch with -qaIncludeSchema or set ate.ai.includeSchema. A new lookupRegionalDish tool replaces the glossary dump, and streaming uses greedy sampling.
- **Photo imports:** Vision now uses the top 10 food labels with their confidences, plus object saliency and the main colours, and all of that goes into the prompt. Two plates of the same food count as one dish, and a spread needs 3 or more different foods. Suggestion chips come from Vision and the model's own guesses, with the SA list only when the labels are ambiguous. Confidence is calibrated from Vision, so an obvious omelette or toast scores above 80%. Thin results (fewer than 3 ingredients or steps, or missing items that are visible in the photo) are regenerated once. Total time is the step times plus a capped prep time. One sandwich serves 1. All-lowercase AI titles are title-cased.
- **Review sheet:** Cancel now sits in a solid nav bar titled "Review your card", instead of floating over the cover.
- **Edit screen:** step times are edited in minutes, labelled "min" (stored as seconds internally). Each ingredient name has its own full-width multiline row, with qty, unit and notes below it. Quick actions like rolling, slicing or serving can't carry a 25-minute AI time unless the step text says so. Thin saved recipes show what's missing (sushi needs nori, rice vinegar and a filling, and vague items like "seasonings" or a "condiment" tag get flagged), with an **Improve with AI** button. Saved lowercase titles are title-cased, except ones you typed yourself.
- **CI:** a report-only probe checks whether the Foundation Models SDK on the runner accepts image input.
- **Tile icons by dish type:** ribs → flame, chicken sandwich → takeaway, drinks → cup. Matching uses whole words ("tea" no longer matches "teaspoon" or "steak").
- **Library header:** the native large title "Your Kitchen", the logo in the toolbar, "Search N recipes" in the search bar, a quiet count, and one icon-only Group & sort menu.
- **Cook mode:** the ✕ is now icon-only with a 44 pt target.
- **Beta:** new checks C-FIX-01…08, C-AI-01…03 and C-LIB-01.

### 🧩 Widgets & Intents
- **Home Screen widgets** (one "ate" widget extension, no new App ID): **Cook timers** (small/medium, live countdown with Pause/Resume and Stop buttons), **Tonight's pick** (small/medium: one recipe from your library that fits today's Health state, tap to open, Cook button on medium), **Shopping list** (small/medium/large, tap an item to tick it off), **Quick add** (small: Link / Photo / Prompt straight into Add recipe) and **Favourites** (medium: 3–4 covers, each opens its recipe).
- **Lock Screen:** circular countdown ring for the next timer, rectangular "Step 4 · Simmer · 12:40 left", and an inline "next shopping item · N more" by the clock.
- **Control Center (iOS 18):** **Kitchen timer** (starts a 5-minute timer, or pauses / resumes the running one; shows its state) and **Add to ate**. Both can go on the Action button and the Lock Screen corners.
- **Siri, Shortcuts and Spotlight:** "Start cook mode in ate" / "Cook Mogodu with ate", "Add milk to my ate list", "What's tonight's pick in ate", "Start a kitchen timer in ate", "Pause / Resume / Stop my ate timer", "Add a recipe link to ate". Recipes are App Entities indexed in Spotlight (IndexedEntity) and open in ate. Adopts Apple's **system search** schema ("Search ate for tripe" opens the Library filtered) and the **journal create-entry** schema (saves to ate's own Insights journal, never Apple's Journal app).
- **Image Playground covers:** recipes with no photo or web image get a Playground cover automatically on Apple Intelligence iPhones (order: your photo → web image → Playground → designed tile). New **Generate cover** in the recipe's … menu; the Add sheet button is now labelled "Generate cover".
- Widgets read a small snapshot in the App Group and reload whenever timers, the list, favourites or the Health state change. Ticks and timer taps made while ate is closed are applied the next time it opens.
- **Beta testing:** new "Widgets, controls & Siri" diagnostics row (App Group, widget extension, which widgets have loaded, Spotlight count) and 16 new checks (A-WIDGET, A-LOCK, A-CONTROL, A-INTENT, A-COVER).

### ✨ Polish
- Sign out's confirmation now opens from the Sign out button itself.
- Delete account warning says recipes you shared stay viewable at their links (privacy audit P5).
- Bar timers for kitchen timers say "Quick timer" and no longer open an empty cook mode.

### ⚠️ Known limits (free Apple ID / Sideloadly)
- Widgets need the App Group to reach ate's data. If Sideloadly re-signs without it, widgets show "Open ate"; Beta testing → Widgets tells you which case you're in. Siri phrases and the Control Center controls run inside ate and keep working either way.
- "Add milk to my ate list" works as one phrase for common items; anything else Siri asks "What should I add?".
- Image Playground needs Apple Intelligence (iPhone 15 Pro or newer) and makes illustrations, not photos.

## 0.1.69 (build 69) and earlier

#### 🔐 Sign-up and reset emails (A-AUTH-02, A-AUTH-05)
- Password rules with live feedback: 8+ characters, a letter and a number, not a common password, strength meter, and the Create account button says why it's disabled. The same policy is now enforced by Supabase (min 8, letters + digits).
- Existing email: Supabase answers with a silent fake success; ate now spots it (empty identities) and says "An account with this email may already exist — sign in or reset your password" with both buttons.
- After sign-up: a clear pending screen with the address, "Didn't get it?" tips (spam, the beta email limit) and Resend with a cooldown timer.
- Email rate limit: "Email limit reached — try again in about an hour" with a countdown that survives relaunch (was "wait a minute"). Real fix needs custom SMTP — see docs/SMTP.md (needs a provider key).

#### 🍲 Better AI for traditional and South African food
- New grounded instructions: dish names and ingredients come from your text verbatim; place names, business names, hashtags, @handles, phone numbers and delivery/ordering text are never used as the recipe. Menus/ads that name a dish get a best-effort traditional recipe with a note; ads that name no dish (e.g. "Traditional food for delivery in Midrand") now stop with a clear message instead of inventing "Traditional Midrand Meal".
- Regional glossary (pap/phutu, ujeqe, mogodu/ulusu, amanqina, morogo, chakalaka, umngqusho, chotlho, braai, boerewors, bobotie, potjiekos, vetkoek, kota, ting, sadza, jollof, egusi, fufu…) with typical ingredients and realistic times; metric units, servings that fit the dish, total time at least the sum of step timers.
- Guided generation with field descriptions and greedy decoding; every AI card shows a confidence (warning under 50%) and any note.
- Instagram: the "N likes, N comments - user on Date:" prefix is stripped and the caption is preferred over og:title.
- Food photos: generic labels (food, meal, potato…) no longer produce a random Western dish. ate asks "What dish is this?" with suggestions; multi-dish spreads let you pick one or several (one card each).
- Tests: caption fixtures (incl. the real Midrand ad), glossary, photo assessment and a prompt snapshot.

#### 🔗 Share links work on the web
- New links: `https://melusi-k.github.io/ate-legal/r/?s=<slug>` (configurable via `ATE_SHARE_URL_TEMPLATE`). Old `lovable.app/r/<slug>`, `/r/<slug>`, `/r/?s=` and `ate://recipe/<slug>` links all still open in the app.

#### 🧪 Tier A beta build
- **More › Beta testing**: all 44 Tier A items (A-CREATE … A-LAUNCH) with IDs, acceptance criteria and live status. Journeys auto-tick ✅ when they really complete on device (imports with their real source, edit/save, delete + Undo, share, opening ate:// links, sign up/in/out, magic link, reset, delete account, sync with rows, timer finish/background/restore, Live Activity start, relaunch with data intact, offline errors, retry after network loss) and ❌ with the captured error when they fail. Manual Pass/Fail/Skip + note for the rest, per-category progress, Export (JSON + Markdown), Reset, and optional upload to Supabase `qa_results` (RLS own rows). First-launch banner on channel builds.
- **"What to expect in this beta"** is now its own page (it was a collapsed, unlocalized disclosure at the bottom of About) and its strings are in the String Catalog.
- **Channel**: `ATE_CHANNEL=TierA` is shown in About, the Settings footer and Beta testing; the ipa is `Ate-0.1.N-buildN-TierA.ipa` and the release tag `build-N-TierA`. CFBundleShortVersionString stays numeric.

#### 🐛 Live Activity
- Every request attempt, skip, update and error is now logged (persisted, last 20) and shown live in More › About › Live Activity — the panel used to show a value captured when the More tab was first built, so it read "no request yet" even while a timer ran.
- Running timers restored after relaunch, or still running when the app returns to the foreground, now re-request their Live Activity.

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
