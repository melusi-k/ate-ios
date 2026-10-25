# Ate — PRD (native iOS)

> **Current implementation audit — 2026-10-24**
>
> This status snapshot is based on the current `main` tree (`1753420743479e76ed732a85a64a9b08a45dfe18`), the tracked open/closed issue and PR inventory, the PRD gap register, and the latest Release readiness workflow run ([run #199](https://github.com/melusi-k/ate-ios/actions/runs/40051574424), workflow conclusion: success). A successful workflow conclusion means the workflow completed; it is **not** evidence that every product acceptance gate passed.
>
> **Overall product status: substantial feature implementation, not yet release-cleared.** The current release-readiness issue records 44/59 checks verified, 6 failing and 9 still open in its generated evidence snapshot. Treat that tally as the latest recorded readiness evidence, not as a fresh rerun of every test on this audit.
>
> **Recently delivered on main**
> - Recipe-generation recovery and lifecycle handling (#143), photo-based recipe grounding/output validation (#144), Settings cleanup/build notes (#145), in-app Terms/Privacy sheets (#149/#172), Foundation Models recipe/progress insights (#84/#160/#164), and the human-centred cooking insights/Cooked Meals collection (#163/#167/#168).
> - CI/release improvements include blocking full-validation UI gates (#170), hosted-share not-found assertion alignment (#171), and dogfood simulator selection/reporting (#173).
> - Issue/PR classification and acceptance-backlog documentation/automation have also landed (#152–#154).
>
> **Open delivery work (audited inventory)**
> - Open PRs: [#166 privacy-safe app/CI telemetry foundation](https://github.com/melusi-k/ate-ios/pull/166) and [#66 journal acceptance UI coverage](https://github.com/melusi-k/ate-ios/pull/66). PR #166 explicitly still requires exact-head Compile Check and Dogfood Qualification, plus a separate Supabase rollout.
> - Highest-impact open product/release work includes [#33 release readiness](https://github.com/melusi-k/ate-ios/issues/33), [#30 release follow-up](https://github.com/melusi-k/ate-ios/issues/30), [#39 sharing/security/release blockers](https://github.com/melusi-k/ate-ios/issues/39), [#40 device QA/support/monitoring](https://github.com/melusi-k/ate-ios/issues/40), [#169 telemetry deployment and verification](https://github.com/melusi-k/ate-ios/issues/169), [#31 Cooking Tracker acceptance](https://github.com/melusi-k/ate-ios/issues/31), [#37 accessibility/responsive/native interaction gaps](https://github.com/melusi-k/ate-ios/issues/37), and [#70 PRD/checklist/QA ownership reconciliation](https://github.com/melusi-k/ate-ios/issues/70).
> - CI regression follow-ups remain open for the full UI shards: [#156 AccessibilityAuditUITests](https://github.com/melusi-k/ate-ios/issues/156), [#157 CoverageUITests](https://github.com/melusi-k/ate-ios/issues/157), and [#158 AteUITests](https://github.com/melusi-k/ate-ios/issues/158). They are tracked work, not a reason to stop feature delivery, but they must not be represented as passing.
>
> **Release risks that remain explicit**
> - Shared-recipe retrieval/deep-link/fallback behaviour and hosted-browser outage cases need verified end-to-end evidence; Universal Links still depend on a paid Apple Developer account, the production domain and AASA hosting.
> - The release-readiness snapshot still reports six failing acceptance checks, including shared-recipe opening/retrieval, deep links/share URL behavior, graceful backend outage fallback, and local-library stability when sync fails.
> - Unit/UI/full-shard evidence must be read from the exact current SHA and actual job results. A green workflow wrapper alone does not supersede failing or skipped inner gates.
> - Physical-device, entitlement, real-account/two-device sync, accessibility and production security evidence remain separate from simulator/source-level completion.
> - Telemetry is not live until the migration and Edge Function are deployed and verified; see #169 and [TELEMETRY.md](TELEMETRY.md).
>
> **Feature-by-feature completion status:** The authoritative current progress matrix is in [MVP_CHECKLIST.md — Current progress snapshot](MVP_CHECKLIST.md), with each area marked completed, partial, outstanding/failing, or not verified and the remaining work stated explicitly. Do not infer completion from an issue being closed where its own closure note defers device/entitlement acceptance.
>
> **Documentation reconciliation rule:** This PRD describes intended product behavior. For completion claims, use current code plus exact-SHA test/device evidence, [MVP_CHECKLIST.md](MVP_CHECKLIST.md), [QA_MATRIX.md](QA_MATRIX.md), and [PRD_GAP_REGISTER.md](PRD_GAP_REGISTER.md). Historical build numbers, old score snapshots, and old backend statements below are not current proof unless revalidated. The detailed requirement sections below are retained; this audit snapshot does not silently mark their acceptance items complete.
>

## Historical hardening plan — originally v1.3 (reconcile with current tracking)

**Release blockers**
1. **Universal links for cross-device sharing.** Associated Domains are placeholder-only on a free Apple ID. Needs a paid account, the ate.app domain, and a hosted AASA file before shared links open the app for other people.
2. **Production security review.** Write and complete a checklist covering RLS on every table, edge-function auth (JWT checks, rate limits, input validation, CORS), data retention and deletion rules, and the service-role key never leaving the server.

**Actions**
3. **Align the docs with real behaviour.** Fix the README (sharing now uses Supabase, not the mock publisher), and state the default runtime mode for AI, sharing, and sync per build type.
4. **Separate config from secrets.** Keep the public values (Supabase URL, publishable key, share host) in one clearly labelled block in `project.yml`, and only ever put real secrets in GitHub secrets or Supabase.
5. **Test auth and sync on real devices.** Sign up, confirm, sign in, magic link, password reset, sign out, delete account, and two-device sync conflicts.
6. **Confirm the Apple Intelligence fallback on every device class.** Cover a supported phone (iPhone 17), one with Apple Intelligence off or unsupported, and one on iOS 18 without Foundation Models. Make sure the badge and the fallback (JSON-LD, demo, or a future server parse) are right, and document the minimum iOS and hardware.
7. **End-to-end coverage.** Add automated tests for auth, sharing (publish, then open on a second simulator), and sync against a staging Supabase project in CI.
8. **Lower integration risk.** Split auth, sync, AI parsing, sharing, timers, and deep links into separate Swift packages or modules with clear interfaces and contract tests, so a change in one area can't quietly break another.

## Apple Health insights + Ate journal (v1.4 MVP) — 2026-10-10

**Architecture.** Apple Health = data source (read-only). Ate = recommendation engine. Apple Journal = limited / future only.

**Research (2026-10-10).**
- HealthKit works with a free Apple ID: Apple's capability table lists HealthKit for the free "Apple Developer" tier ([Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios)). The unsigned CI IPA is ad-hoc signed with `Ate/Ate.entitlements` (now incl. `com.apple.developer.healthkit`), so Sideloadly can carry it into the free profile. If a re-sign drops it, the app detects that from `embedded.mobileprovision` and shows "signed without Apple Health access" instead of a misleading Settings hint.
- Journaling Suggestions (`JournalingSuggestionsPicker`, iOS 17.2+) is a **picker that reads** a moment the user selects from the system's suggestions into the app. It is **not** a way for Ate to put suggestions into Apple's Journal app. It needs `com.apple.developer.journal.allow`, which Apple lists for the paid Apple Developer Program only ([entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.journal.allow), [framework](https://developer.apple.com/documentation/journalingsuggestions)).
- No API lets a third-party app write entries or suggestions into Apple Journal. The only indirect route Apple describes: data an app saves to HealthKit, or donates via SiriKit/CallKit, *may* surface in Journaling Suggestions, chosen by the system ([Apple forums 740559](https://developer.apple.com/forums/thread/740559), [Journaling Suggestions & Privacy](https://www.apple.com/legal/privacy/data/en/journaling-suggestions/)). So Health meal logging (write) is also our best chance for Ate meals to show up in Journal.

**MVP scope (built).**
- `HealthKitService` (protocol + live + mock via `-qaMockHealth <recovery|lowEnergy|performance|underactive|empty|denied|unavailable>`): read-only sleep, steps, active energy, workouts, last 1–7 days. Heart rate / resting energy later; body mass only on explicit opt-in (not requested).
- Incremental permission: nothing is asked at launch; the ask happens only when the user taps "Connect Apple Health" in Insights, and only for the four MVP types. No write types → no `NSHealthUpdateUsageDescription`.
- `HealthInsightEngine`: recovery / low-energy / performance / underactive / balanced, with plain-language reasons.
- `RecipeHealthMatcher`: top 3 saved recipes for the state (ingredient/tag heuristics, not nutrition advice).
- `JournalSuggestionService`: 1–2 prompts; Foundation Models when available, templated fallback.
- `JournalEntry` (SwiftData, separate local store, never synced).
- UI: In beta-channel builds, open Settings › Beta testing › Open Insights & journal (Your body today · Suggested meals · Reflect on your day · Save to journal · Your Ate journal), plus a "Today" card in Library once Health has data.
- States: unavailable, entitlement missing, denied, no data.
- Journaling Suggestions picker: compiled in, shown only when the installed profile has `com.apple.developer.journal.allow` (hidden on free-ID builds). Picking a photo moment starts a journal prompt about that meal; a workout moment points to recovery meals.

**Journaling Suggestions design (v1.4.1, patterns from robbiet480/Dispatch #33).**
- Picker READS a moment the user chooses; Ate never pushes suggestions into Apple's Journal app.
- `JournalingMomentMapper` (pure, framework-free, unit-tested) maps (title, DateInterval?, photos?, workout?) → recipe draft (food-ish title + photo) or a prefilled Ate journal entry. `JournalingSuggestions` is imported only in `JournalingSuggestionsBridge.swift` (app target, device only).
- Additive schema only: `RecipeSource.journalMoment`; `JournalEntry.journalingSuggestionTitle`, `momentDate`, `sourceRaw` (defaults, lightweight migration).
- Settings → "Journaling Suggestions" toggle, OFF by default, disabled unless the installed profile carries the entitlement.
- Never presented under UI tests; tests cover the mapper and the "From a Journal moment" context row (entries) / source badge (recipes).
- `com.apple.developer.journal.allow` is a request-based entitlement on a paid team. External, non-blocking checklist item: **EXT-JOURNAL-01 — request the entitlement once the paid Apple Developer account exists**; nothing else waits on it.

**Insights hardening (lessons from SebaKrk/StepTrackerTCA).** Permission-prompt regression UI test (mock prompt via `-qaHealthPrompt`); ContentUnavailableView for empty/denied/unavailable/unsigned with Open Settings / Try again / Use sample data (beta + tests); load once on first appear + pull-to-refresh; simulator falls back to sample data after authorization; 7-day steps sparkline (Swift Charts); all reads behind `HealthKitServicing` for injection.

**Later phases.**
1. Health meal nutrition logging (write dietary energy/macros after cooking; adds `NSHealthUpdateUsageDescription`, per-recipe nutrition estimates).
2. Paid account: add `com.apple.developer.journal.allow` to `Ate-Signed.entitlements`, enable the picker; "dinner photo → recipe" via the photo import pipeline.
3. "Ate suggestions in Apple Journal": only if Apple opens an API. Not planned.

## Nutrition tracking — Phase 1 goals foundation (2026-10-25)

Issue [#179](https://github.com/melusi-k/ate-ios/issues/179) is being delivered incrementally. PR [#180](https://github.com/melusi-k/ate-ios/pull/180) implements the local configurable-goals foundation only:

- Daily targets for energy (kcal), protein, carbohydrates, fat and fibre (grams) are independently optional.
- Targets are validated, stored in canonical units, and persisted locally through an injectable `UserDefaults` repository.
- Settings exposes an accessible native SwiftUI form with draft editing, explicit **Clear all goals**, validation errors, Save and Cancel.
- Unit and UI regression coverage covers persistence, malformed data, validation boundaries, Settings navigation, accessibility identifiers, clearing and reopening.

This phase does **not** calculate recipe nutrition, map ingredients to foods, provide a food diary, derive daily/weekly consumed totals, or write nutrition data to HealthKit. Those remain follow-up phases under #179. Goals are personal targets and are not recommendations.

## Nutrition data-source decision (2026-10-25)

For the customer-facing starter catalogue, use a small offline bundle of exact-match USDA FoodData Central records. FDC is public domain under CC0 1.0 and requests source attribution; its live API requires a protected key, so the app will not call it at runtime. Store the source record ID, data type/release, preparation state, reference quantity, units and only the nutrients present in the source. See [Nutrition data policy](NUTRITION_DATA_POLICY.md).

Do not approximate South African foods or prepared dishes with a superficially similar FDC record. Show foods without an exact match as not in the catalogue and preserve their nutrient values as unavailable unless the person adds values from a source they identify; those values remain user-provided, not independently verified by Ate. Add SAFOODS records only after commercial-use rights are confirmed in writing. The bundled catalogue itself is still empty/unverified in the current mainline; this decision resolves the source strategy, not catalogue coverage.

**MVP checklist / QA**
| ID | Check | How |
|---|---|---|
| H-01 | No Health prompt at launch | manual |
| H-02 | Connect asks only sleep/steps/energy/workouts, read-only | device |
| H-03 | Recovery state + 3 suggestions from mock data | UI test `testHealthInsightsRecoverySavesJournalEntry` |
| H-04 | Save to journal persists locally | UI + unit (`JournalStore`) |
| H-05 | Denied / unavailable / no-data copy | UI test `testHealthInsightsDeniedAndUnavailable` |
| H-06 | Free-ID sideload installs, Health connects on device | device |
| H-07 | Journaling picker hidden on free-ID build | UI + unit |
| H-08 | Engine/matcher rules | unit `HealthInsightTests` |

## Beta gate & QA release gate

**PRD gap register:** [docs/PRD_GAP_REGISTER.md](PRD_GAP_REGISTER.md) maps the PRD, MVP checklist, QA matrix, and known external dependencies to tracked GitHub issues. This register is an index; the detailed acceptance criteria remain in [MVP_CHECKLIST.md](MVP_CHECKLIST.md).


- **Beta / launch gate:** [MVP_CHECKLIST.md](MVP_CHECKLIST.md) — tiered: **A** must-pass before pilot, **B** before public launch, **C** later polish; every item has a user journey, acceptance criteria, verification and an honest status. Platform constraints and pilot vs public rollout criteria are up front and at the end. Scored pass/fail test matrix: [QA_MATRIX.md](QA_MATRIX.md); scores: [MVP_SCORE.md](MVP_SCORE.md); tester FAQ: [SUPPORT.md](SUPPORT.md). Auth (with a real-device gate) and backend/share are launch gates. Verdict (build 36): pilot candidate, but Tier A isn't green yet; not public-launch ready.
- **QA pass on key flows (release gate criteria):** a build may only be published when all 8 flows pass in `KeyFlowsQATests` — 1 add from URL (JSON-LD + social caption), 2 add from photo (screenshot + food-photo fallback), 3 generate & edit, 4 save, 5 share (link + text, single link), 6 open shared (`ate://recipe/<slug>` + expired/not found), 7 sync (sign in, edit, sync, second launch pulls), 8 timers (start/pause/resume, timer bar, finish chime/haptic, Live Activity request). CI writes the flow → pass/fail table into the job summary and release notes. Before giving a build to testers, run the manual on-device checklist in [QA.md](QA.md).
- Hardening landed with the gate: clear session-expiry handling (local sign-out, recipes kept), account-switch safety, idempotent repeat syncs (fixed a re-push loop from fractional stamps), a 500-recipe performance test, AI transparency copy in onboarding and Settings, and an in-app "What to expect in this beta" note ([BETA.md](BETA.md)).

## Feature additions (v1.2) — 2026-10-10

### F. Sign-in reliability fix
- **Bug:** signing in from Settings showed "The network connection was lost." (NSURLErrorNetworkConnectionLost, -1005). That's a transport error, not an auth error: the request never got a response. The server side was fine (curl with the app's exact headers returned normal JSON errors on both the old and new projects). The likely cause is `URLSession.shared` reusing a dead pooled connection, typically an HTTP/3 (QUIC) one. Supabase advertises `alt-svc: h3`, and iOS suspends those connections when the app is backgrounded, for example while you switch to Mail.
- **Fix:** all Supabase calls go through `Net`: a dedicated session, `assumesHTTP3Capable = false`, 20 s timeouts, and **one automatic retry on -1005**. `sb_publishable_…` keys are no longer sent as `Authorization: Bearer` (they aren't JWTs). Only `apikey` is sent, plus `Bearer <user JWT>` when signed in.
- **Friendly errors:** wrong email/password, email not confirmed (with resend), rate limited, already registered, weak password, expired link, offline/timeout/unreachable server.
- Note: there is no account for melusi.l.k@gmail.com on either backend yet (both `auth.users` tables were empty), so the first step is **Create account**.

### F1b. Tab bar navigation (v1.3)
- Native `TabView` with three tabs: **Library** (`books.vertical`), **Shopping list** (`basket`, badge = unticked items) and **Settings** (`gearshape`). These replace the push navigation and the header icons that used to lead to Shopping and Settings.
- Each tab has its own `NavigationStack` (`path`, `shoppingPath`, `settingsPath` in `AppStore`), so its state is kept when you switch. Re-tapping the current tab pops it to the root.
- The sticky timer bar is a bottom safe-area inset inside each tab, so it sits above the tab bar. Cook mode and onboarding are full-screen covers that hide the tab bar.
- Deep links select a tab: `ate://recipe/…`, `ate://r/…`, `ate://cook/…` and `ate://import` go to Library, and `ate://auth-callback` goes to Settings.
- Built with the iOS 26 SDK, so it gets the Liquid Glass tab bar by default, tinted in the brand orange.

### F1d. Adaptive sidebar, collections and filters (v1.3)
- **Navigation:** iOS 18+ `TabView` keeps the main bar focused on Library, Shopping (with unticked-item badge), Insights and Settings; iOS 26 adds the dedicated Search-role tab and Add recipe bottom accessory. Beta checks and expectations live at Settings › Beta testing, alongside account, preferences, data tools and About diagnostics. No dedicated More tab ships. Recipe detail hides the tab bar. Info.plist supports portrait + both landscapes; landscape library is a 2-column grid (adaptive min 220pt). Deployment target iOS 18.
- **Library layout:** single-column list in portrait. In landscape or a regular width it becomes an adaptive `LazyVGrid` of thumbnail cards (min 250 pt, so 2 columns on a landscape iPhone and 3+ on wider screens).
- **Collections:** Quick (<30 min), Favourites (`favorite` flag, star in detail and the long-press menu), Recently added (newest 20), Recently cooked (`lastCookedAt`, stamped when cook mode opens), and an auto-collection per main ingredient (`IngredientTags.main`). Selecting one sets `RecipeFilter.collection`.
- **Filter chips (both orientations):** time ≤15/30/60, origin (`RecipeOrigin` link/photo/prompt/shared, inferred for legacy cards), servings 1–2/3–4/5+, Favourites, and ingredient tags auto-extracted from ingredient names (whole-word keyword table, plus vegetarian/vegan when no meat, fish or animal products). Values OR within a group and groups AND together. There's a result count and Clear (n), and the filter persists in UserDefaults.
- **Groundwork:** the size-class-driven split view and adaptive grid are the base for the iPad kitchen display and the foldable "duo" phases below.

### F1e. Group, sort, reorder, swipe (v1.3)
- `LibraryLayout` (persisted): **Group by** None / Recently added (Today, This week, Earlier) / Cuisine (`RecipeCard.cuisine`, generated by Foundation Models via `@Guide`, editable in the editor, "Other" last) / Main ingredient (`IngredientTags.main`) / Cook time (≤15, <30, <60, 60+, no time). **Sort** Newest / A–Z / Quickest / Recently cooked / Favourites first / My order (`sortIndex`, part of the synced recipe JSON; never-ordered new cards come first).
- Drag to reorder in My order with no grouping: `List.onMove` for the list, `draggable`/`dropDestination` for the grid. `.contentShape(.dragPreview / .contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radius))` means no white rectangle shows behind the rounded cards.
- List rows: trailing full-swipe Delete with a 5 s Undo toast, and leading Favourite plus Add to list. Context menu everywhere: Cook, Share, Favourite, Add to shopping list, Delete, with a card preview.
- **Not done, and why:** sections are built by `LibraryLayout.sections` over the in-memory store, not SwiftData `@Query(sort:sectionBy:)`. The library isn't `@Query`-driven: recipes live in `AppStore` and SwiftData holds JSON blobs for sync, so there's no model key path to section by. I also couldn't confirm a `sectionBy:` API in the iOS 26 SDK. In the grid, cards get the context menu but no swipe actions: I couldn't confirm a `.swipeActions` on arbitrary views or a `.swipeActionsContainer()` in the SDK, so I didn't ship code against unverified APIs. Revisit both when building on a Mac with the current SDK.

### F1c. "Save to ate" share extension (v1.3)
- `AteShare` target (`com.melusik.ate.share`) accepts 1 web URL, text (it pulls the first link out of a caption) or 1 image.
- It queues the item in the App Group (`SharedInbox`, images in `Inbox/`) and offers **Open ate** (`ate://import`). The app picks the item up when it becomes active and opens the Add sheet prefilled, with generation already started.
- With no App Group (free-account sideload), it copies the link to the clipboard instead.

### F2. Sync "HTTP 400" fix (build 14)
- **Symptom:** after signing in, Settings showed "Sync failed: Sync failed (HTTP 400)".
- **Root causes (both confirmed with curl against `user_recipes`):**
  1. `updated_at` was a Swift `Double` built from `Date().timeIntervalSince1970 * 1000`, so it went out as e.g. `1760076000123.456`. The column is `bigint`, so PostgREST rejected it with **22P02** "invalid input syntax for type bigint". Even `…123.0` is rejected.
  2. Swift's synthesized `Encodable` **omits** `nil` optionals, so tombstones (`data == nil`) had no `data` key. In a bulk upsert mixing upserts and deletes, PostgREST requires identical keys and returns **PGRST102** "All object keys must match".
- **Fix:** `SyncRecord.updated_at` is `Int64` (stamps are rounded when created, and decoding accepts ints, floats or numeric strings). A custom `encode(to:)` always writes `data` (`null` for deletes). Sync status now shows PostgREST's `code: message`.
- **Checks:** RLS still rejects a foreign `user_id` (42501), and the `kind` check constraint rejects anything but `recipe`/`shopping` (23514). Unit test `testSyncRecordEncodesIntegerStampsAndNullData`.

### G. Onboarding
- Shown once on first run (`ate.onboarded.v1`): 3 pages (import from link/screenshot/prompt; cook mode with timers; sync and share), then **Create account / Sign in / Continue without account**, with Skip and page dots. Replay it from **Settings › About › Replay intro**. It shows again after account deletion.

### H. Auth screen (sheet)
- Sign-in / Create-account modes, show/hide password, keyboard-friendly (Next/Go, interactive dismissal), loading states, inline errors.
- **Forgot password?** calls `POST /auth/v1/recover` with `redirect_to=ate://auth-callback`. The link opens the app on a **Choose a new password** screen (`PUT /auth/v1/user`).
- **Magic link** (`/otp`), and an **email-confirmation pending** state with **Resend** (`/resend`).
- `ate://auth-callback` handles PKCE `?code=` (exchanged with the verifier stored in the Keychain), implicit `#access_token…&type=recovery|signup|magiclink`, and `#error…`. A link opened on another device just says the email is confirmed and asks you to sign in.

### I. Account management
- Settings › Account & sync shows the email, sync status, Sync now, and **Sign out** with a choice: keep recipes on this iPhone, or remove local data.
- **Delete account** (danger zone): an alert, then type **DELETE**. It calls the Edge Function **`delete-account`**, which verifies the user's JWT, deletes their `user_recipes` rows (and owned `shared_recipes` if an owner column ever exists; today shares are anonymous and stay), then deletes the auth user with the admin API. The app then wipes its session and local data and returns to onboarding. This covers Apple's account-deletion requirement (5.1.1(v)).

### K. Visible build identity
- The Settings footer shows `ate 0.1.N (build N) · <short sha> · backend <project ref>`; tap it to copy. The version and build also show in Settings › About and on the onboarding choice page.
- `CFBundleShortVersionString` is `0.1.<run_number>`, so iPhone Storage shows a different version for each build.
- Downloads are named `Ate-0.1.N-buildN.ipa`. There's no more plain `Ate.ipa`.

### J. Legal links
- ✅ **Live:** https://melusi-k.github.io/ate-legal/privacy.html and https://melusi-k.github.io/ate-legal/terms.html. Source is `docs/legal/*.md`, rendered by `scripts/build-legal.py` into the public repo `melusi-k/ate-legal`, because GitHub Pages on the private repo needs a paid plan. The links show on the auth sheet, the onboarding choice page and Settings › About.

## Feature additions (v1.1) — 2026-10-10

### A. Live Activity for cook-mode timers
- ActivityKit plus a WidgetKit extension (`AteWidgets`, `com.melusik.ate.widgets`) embedded under `Ate.app/PlugIns/`. CI fails the build if it's missing. `NSSupportsLiveActivities = YES`.
- `CookTimerAttributes` (shared): recipe ID/title and timer ID. State: step index/count, step text, start/end date, remaining, total, finished.
- **Lock Screen:** recipe name, "Step i of n" (· paused), step text, and a big countdown via `Text(timerInterval:countsDown:)`. Shows a static m:ss when paused.
- **Dynamic Island:** compact (timer icon + countdown), minimal (timer/pause icon), expanded (step label, countdown, recipe title, step text). Tapping opens `ate://cook/<recipeID>`.
- **Lifecycle:** start on timer start; update on pause/resume/reset; end when the timer finishes (stays 2 min showing "Done") or is stopped. When you exit cook mode, idle (paused/reset) timers and their activities end. **Running** timers keep their activity and appear in the timer bar, since that's the point of a Live Activity.

### B. Sticky in-app timer bar
- `TimerCenter` (app-wide, `@Observable`) owns every cook timer. Several can run at once, one per recipe step.
- The bar is a `safeAreaInset(.bottom)` on the root, so it shows on every screen whenever a timer exists and cook mode isn't open. Each row shows the recipe, step, (paused) and a live countdown. Tapping it reopens cook mode on that step; there are pause/resume and stop buttons.
- Cook mode shows chips for other running steps of the same recipe. Timers no longer reset when you change steps.

### C. Accounts and cross-device sync (Supabase)
- Free Apple IDs can't use CloudKit or Sign in with Apple, so this uses **Supabase Auth** over REST: email/password sign-up and sign-in, plus a **magic link** (`redirect_to=ate://auth-callback`). The session is stored in the Keychain and refreshed automatically.
- Config: `ATE_SUPABASE_URL=https://ploncuhexmwydjxljuhe.supabase.co` (Melusi's own Supabase project `ate`, eu-west-1) and its publishable key. Both are public; RLS enforces access. Email sign-up is on, `ate://auth-callback` is in the redirect allow list, and confirmation emails are required (default Supabase mailer).
- Table `public.user_recipes(user_id, kind 'recipe'|'shopping', id, data jsonb, updated_at bigint ms, deleted)`, PK `(user_id, kind, id)`, RLS `auth.uid() = user_id`. Migration: `supabase/migrations/20261010000000_user_recipes.sql`. Applied to production on 2026-10-10.
- **Sync:** offline-first (SwiftData stays the source of truth), last-write-wins per item using client timestamps, deletions recorded as tombstones. It runs on sign-in, when the app becomes active, ~1.5 s after local edits, and from "Sync now". Pull, then merge (`SyncMerge`, unit-tested), then upsert (`Prefer: resolution=merge-duplicates`).
- **Graceful degradation:** signed-out works exactly as before. A missing table (404 / PGRST205) shows "Cloud sync isn't set up on the server yet" and never blocks the app.
- **Settings → Account & sync:** email, password, Sign in / Create account / Email me a magic link; when signed in, email, sync status, Sync now and Sign out. Signing out keeps your local data.
- `-UITesting` uses `MockAuth` (password `password123`) and an in-memory `MockSync`.

### D. Sharing
- **Share link** (default) sends **one** URL item through a `UIActivityItemSource` with `LPLinkMetadata` (title = recipe name, icon/image = the rendered recipe thumbnail), so Messages shows a rich preview card. The old code shared both the text (which contained the URL) and the URL, so the link appeared twice.
- **Share as text** sends the cleaned text only: title, description, "N servings · M min", "Ingredients" with • bullets, "Steps" numbered in sentence case, optional "Source:", and a single final line "View in ate: <link>".
- Links are `https://recipe-transform-ai.lovable.app/r/<slug>`, set in **one config value** `ATE_SHARE_HOST`, ready to switch to `https://ate.app`.
- Custom scheme: `ate://recipe/<slug>` (canonical) plus `ate://r/<slug>` (alias) open the Shared recipe screen. `ate://cook/<id>` opens cook mode. Associated Domains placeholders live in `docs/associated-domains/` (needs a paid account).
- Publishing goes to the `publish-recipe` Edge Function on the new backend; the app reads shares from `shared_recipes`. The 9 existing Lovable shares were copied with their slugs, so old links still resolve in the app. ⚠️ The Lovable web page still reads the **old** backend, so links to recipes shared from iOS after 2026-10-10 open in Ate (via `ate://`) but show "not found" on the web until Lovable is repointed.

### E. Build & platform plumbing
- **Build number and version:** CI sets `MARKETING_VERSION=0.1.<run_number>`, `CURRENT_PROJECT_VERSION=<run_number>` and `ATE_GIT_SHA`, then checks them inside the built `.ipa` (the job fails on a mismatch). Each build is published as `Ate-<version>-build<N>.ipa`: it is the only asset on the rolling `latest-build` prerelease, and it also goes on a permanent `build-<N>` prerelease. Settings shows `ate <version> (build N) · <sha> · backend <ref>` (tap to copy).
- `PrivacyInfo.xcprivacy` (app + widget): `NSPrivacyTracking=false`, UserDefaults reasons CA92.1 + 1C8F.1 (App Group). The app declares Email, User ID and Other User Content (linked, App Functionality) for Supabase sync.
- Entitlements: App Group `group.com.melusik.ate` for Ate + AteWidgets. Cook timers persist to the group `UserDefaults` and fall back to `.standard` if the container is nil (possible on free-ID sideloads). Signed builds use `Ate-Signed.entitlements`, which adds `applinks:ate.app` and `applinks:recipe-transform-ai.lovable.app`. Unsigned builds are ad-hoc codesigned with the App Group entitlements so Sideloadly can carry them over. `DEVELOPMENT_TEAM` comes from the `TEAM_ID` env/secret.

## Review findings (v1.1 review)
Fixed:
1. The share link appeared twice (text + URL items). Fixed in D.
2. Step instructions were shared in lowercase. Now sentence case.
3. Deleting ingredient/step rows in the editor could crash from stale index bindings. Now bounds-checked.
4. The delete confirmation button had the same label as the trash icon ("Delete"), which was ambiguous for VoiceOver and tests. Renamed "Delete recipe".
5. Timers reset whenever you changed steps in cook mode, and only one could exist. Now handled by `TimerCenter` (multi-timer, survives navigation).
6. Without the edge functions deployed, the on-device fallback could route to the Supabase backend. The fallback is now always the mock.
7. Deleting a recipe left its timers running. They're now stopped.
8. The timer bar covered the floating "Add recipe"/"Cook mode" buttons. The bar is now a per-screen safe-area inset, so the buttons sit above it.
9. The demo card description told users to "connect Supabase for real AI" (wrong since the on-device switch). Copy fixed.
10. Running cook timers were lost when the app was killed. They now persist (App Group) and restore on launch.

Open issues / gaps vs PRD:
- **Web share page on old backend:** new iOS shares don't render on `recipe-transform-ai.lovable.app` until the Lovable app points at project `ploncuhexmwydjxljuhe` (needs Lovable credits).
- **AI:** ✅ Foundation Models verified on a real iOS 26 device (iPhone 17, 2026-10-10). Queries return real, relevant recipes. ✅ URL import now parses schema.org JSON-LD first, with no AI call (`JSONLD.swift`, tagged `source: jsonLD`). Still open: without Apple Intelligence the app returns mock cards (badged “Demo”); a server fallback (`parse-recipe`) isn't deployed because there's no AI provider key on the new project.
- **Provenance:** every card stores `source` (`appleIntelligence | jsonLD | mock | manual | shared | imported | unknown`) and `generatedAt`. Recipes saved before v1.3 decode as `unknown`, with no badge. The badge shows on the review step and the recipe detail. Settings › About › AI diagnostics shows model availability and the last run's source, mode and latency.
- **Sync:** client-clock LWW, so a wrong device clock can win. There's no field-level merge. Signing into a different account merges the local library into it.
- **Signed IPA path:** the extension needs its own provisioning profile. The signed CI path currently passes only one profile, so signed builds with the widget will fail until a second profile secret is added. Unsigned builds plus Sideloadly are fine.
- **Timer chime:** uses system sounds, not the 3-tone chime asset. Haptics are a single success tap.
- **Not built:** aisle grouping in the shopping list (optional), voice commands in cook mode, the "Save to ate" share extension, the camera option.
- **Branding:** the logo is an SF Symbol stand-in; real `ate-logo.png` assets still need importing.
- **Library:** Clear all doesn't clear the shopping list (by design, but worth stating in the UI).

## Future phase — StoreKit / Ate Plus (planned, not in current build)

Status: planned. Docs only; no app code yet. Blocked on a **paid Apple Developer Program account** ($99/yr), which is needed for App Store Connect products, sandbox testers, App Store Server API keys and TestFlight. Same dependency as Journaling Suggestions; schedule both together.

### Free core vs Ate Plus
Free forever: recipe library (add, edit, sections, sort, search), cook mode, timers + Live Activities/Dynamic Island, shopping list, accounts + cross-device sync, sharing, Siri/Shortcuts basics, a basic widget, a fair AI allowance (e.g. 10 AI imports/regenerations a month).

Ate Plus candidates:
- Unlimited AI imports, regenerations and "Ask Ate" revisions
- Image Playground covers (on-device AI cover generation)
- Health-aware meal plans (Apple Health insights)
- Extra widgets, Lock Screen widgets and app themes/icons
- Ate journal export (PDF/CSV)
- Optional later: online photo check for hard dishes (if approved)

Rule: never gate data the user already owns. Recipes made with Plus features stay readable, cookable and exportable after a lapse.

### Tier and pricing — DECISION: Option B (chosen 2026-10-11)
**Chosen: B. Single tier "Ate Plus" + lifetime**, **7-day free trial on the annual plan only** (introductory offer configured on `com.melusik.ate.plus.annual`, new subscribers only; eligibility checked with `isEligibleForIntroOffer`). Monthly and lifetime have **no trial**. ZAR prices are App Store price points, so final figures snap to Apple's tier table.

| Product | Price | Product ID | Type |
|---|---|---|---|
| Ate Plus Monthly | R49.99 / $3.99 | `com.melusik.ate.plus.monthly` | Auto-renewable (group "Ate Plus"), no trial |
| Ate Plus Annual | R399.99 / $29.99 (~33% off) | `com.melusik.ate.plus.annual` | Auto-renewable (same group, same level), 7-day free trial (intro offer, annual only) |
| Ate Plus Lifetime | R999.99 / $69.99 once | `com.melusik.ate.plus.lifetime` | Non-consumable, Family Sharing on, no trial |

Rejected alternatives (kept for reference):
- ~~A. Simple single tier: R39.99 / $2.99 monthly, R349.99 / $24.99 annual, no lifetime~~ — rejected: no one-off purchase for users who dislike subscriptions.
- ~~C. Two tiers: Plus R29.99 / $1.99 (R249.99 / $16.99 yr) and Plus Family Kitchen R59.99 / $4.99 (R499.99 / $39.99 yr)~~ — rejected: more review, paywall and support overhead; harder to explain.

### Lifetime entitlement handling
- Plus is active if **any** of: a verified, non-revoked `com.melusik.ate.plus.lifetime` transaction in `Transaction.currentEntitlements`, or an active/grace-period/billing-retry subscription in the "Ate Plus" group.
- Lifetime wins: when present, entitlement source = `lifetime`, `expires_at = null`, and subscription expiry/renewal events don't remove Plus.
- Subscriber buys lifetime: paywall prompts them to cancel the subscription via `.manageSubscriptionsSheet` (Apple won't auto-cancel); app shows "You own Ate Plus Lifetime — cancel your subscription to stop renewals". Lifetime product is hidden from the paywall once owned; subscriptions are hidden too.
- Revocation (`revocationDate` set, refund via Apple, or Family Sharing removed) removes lifetime Plus; fall back to any active subscription, otherwise free. Content is never deleted.
- Family Sharing: `ownershipType == .familyShared` lifetime counts as Plus; revoked if the family member leaves.
- Restore (`AppStore.sync()`) restores lifetime on new devices; App Group cache stores `{source: lifetime|subscription, productId, expiresAt|null}` for widgets/App Intents.
- Server: `entitlements.product_type` (`subscription` | `lifetime`), lifetime rows have `expires_at = null`; Edge Function handles `REFUND`/`REVOKE` notifications for the non-consumable. Server status = lifetime OR active subscription.
- Tests: lifetime purchase unlocks; lifetime + active sub shows lifetime; sub expires while lifetime owned keeps Plus; lifetime refund falls back correctly; family-shared lifetime; restore on clean install.

### Technical design (StoreKit 2)
- Products defined in App Store Connect; one subscription group "Ate Plus" (monthly + annual, same level). Lifetime `com.melusik.ate.plus.lifetime` is a non-consumable.
- Paywall: `SubscriptionStoreView` (+ `.subscriptionStoreControlStyle`, marketing header, policies), `ProductView` for lifetime. Entry points: AI limit reached, Playground cover button, meal plans, settings > Ate Plus.
- `EntitlementManager` (@Observable): reads `Transaction.currentEntitlements` at launch; listens to `Transaction.updates` for the whole app lifetime; calls `transaction.finish()`; handles revocation, refunds, expiry, grace period and billing retry via `Product.SubscriptionInfo.Status`.
- **Restore purchases** button in the paywall and Settings (`AppStore.sync()`).
- **Entitlement caching in the App Group** (shared `UserDefaults`/file with expiry date + product id) so widgets, the Live Activity and App Intents can check Plus without StoreKit calls; refreshed on each update.
- Server-side validation: Supabase Edge Function `appstore-notifications` receives **App Store Server Notifications V2** (JWS verified against Apple root certs), and `verify-transaction` calls the **App Store Server API** (Get Transaction Info / subscription status) with the signed transaction from the device. Results land in an `entitlements` table (user_id, original_transaction_id, product_id, status, expires_at, environment, updated_at) with RLS so a user only reads their own row. `appAccountToken` = Supabase user UUID links purchases to accounts. Server is source of truth for sync across devices; on-device StoreKit is the offline fallback.
- **Family Sharing** enabled on subscriptions (and lifetime); handle `ownershipType == .familyShared`.
- **Offer codes** (one-time codes for testers/partners) via `.offerCodeRedemption`; **intro offer** = 7-day free trial on annual only (none on monthly; non-consumables can't have one); promotional/win-back offers later.
- Manage subscription: `.manageSubscriptionsSheet`; refund request: `.refundRequestSheet` (Apple handles refunds).

### App Review rules
- **3.1.1**: digital features must be unlocked via In-App Purchase only; no external payment links or prices for them.
- **3.1.2**: auto-renewing subscriptions must give ongoing value, run at least 7 days, work on all the user's devices, and must not take away features the user already has.
- Required disclosure on the paywall (near the buy button): title, length, price per period, free-trial length, and: "Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions in your App Store account settings."
- Functional links to **Terms of Use (EULA)** and **Privacy Policy** in the paywall, Settings and App Store Connect metadata.
- Restore purchases must be available; no misleading trial copy.
- Paywall copy notes (trial is annual-only):
  - Annual option: "Try 7 days free, then R399.99/year" (localized price from `Product.displayPrice`), shown only if the user is eligible; ineligible users see "R399.99/year".
  - Monthly option: "R49.99/month", with no trial wording anywhere near it.
  - Lifetime: "R999.99 once — no subscription".
  - Never use a generic "Start free trial" button that could apply to monthly; the trial line sits on the annual option only. Disclosure mentions the trial converts to the annual price unless cancelled at least 24 hours before it ends.

### Legal pages to update (ate-legal)
- Terms: subscriptions section (auto-renewal, trial, price changes, cancellation, Family Sharing, what happens to content after lapse); refunds handled by Apple per its policies, with link to reportaproblem.apple.com.
- Privacy policy: purchase data (Apple transaction IDs, entitlement status) stored in Supabase; no card data ever received.
- New/updated: subscription FAQ / support page; reference Apple's standard EULA or custom EULA.

### Testing
- `Ate.storekit` StoreKit configuration file (all products; 7-day free intro offer on annual only, none on monthly; offer codes; Family Sharing) wired into a test scheme; sandbox testers later.
- Unit tests (StoreKitTest `SKTestSession`): purchase, trial, renewal, expiry, refund/revocation, grace period, restore, Family Sharing, App Group cache read/write, AI quota counting.
- Trial tests: annual shows and grants the 7-day trial for eligible users; monthly purchase starts paid immediately with no intro offer; lifetime has none; ineligible user (past annual trial) gets no trial; trial converts to paid annual; cancelling during trial ends Plus at trial end.
- UI tests: trial copy appears only on the annual option; monthly and lifetime show no trial text.
- UI tests: paywall shows prices + disclosure + Terms/Privacy links; purchase unlocks Playground covers; restore flow; lapsed user keeps recipes.
- Edge Function tests: JWS verification (valid/forged), each notification type updates `entitlements`, idempotency.
- CI: StoreKit unit tests join the release gate; no real purchases in CI.

### Acceptance criteria
- [ ] Free users can use library, cook mode, timers, sync and sharing with no paywall.
- [ ] Paywall uses `SubscriptionStoreView`, shows localized ZAR/USD prices, the 7-day trial on annual only (none on monthly/lifetime), disclosure text and working Terms/Privacy links.
- [ ] Purchase, restore and Family Sharing unlock Plus within 2 s; entitlement survives relaunch and offline.
- [ ] Widgets and App Intents respect Plus via the App Group cache.
- [ ] Refund/expiry/revocation removes Plus within one notification cycle without deleting user content.
- [ ] Server `entitlements` row matches device state across two devices on one account.
- [ ] Offer code redemption works; intro trial only offered on annual and only to eligible users.
- [ ] Legal pages updated and linked before submission; app passes review against 3.1.1/3.1.2.
- [ ] All StoreKit unit, UI and Edge Function tests green in CI.

### Open questions
1. ✅ Resolved: Option B — R49.99 / $3.99 monthly, R399.99 / $29.99 annual, R999.99 / $69.99 lifetime, 7-day trial on annual only.
2. ✅ Resolved: 7-day free trial on the annual plan only; monthly and lifetime have no trial.
3. Free AI allowance size (5, 10, 20 a month), and does it apply to signed-out users?
4. ✅ Resolved: yes — `com.melusik.ate.plus.lifetime` non-consumable, Family Sharing on.
5. Family Sharing on from day one?
6. Grandfather beta testers with offer codes or free Plus period?
7. Apple's standard EULA or a custom one?
8. Small Business Program enrolment (15% commission) — yes?
9. Which features are definitely Plus vs free (e.g. journal export)?
10. Launch Plus with v1.x or wait for the paid-account phase alongside Journaling Suggestions?

## Updated roadmap
1. ✅ **Done (2026-10-10):** backend moved to Melusi's own Supabase project `ate` (`ploncuhexmwydjxljuhe`): `shared_recipes` (9 rows, slugs kept) + `user_recipes` with RLS, Edge Functions `publish-recipe` and `get-shared-recipe`, email auth + `ate://auth-callback`. The app publishes and reads shares there.
2. **Before TestFlight:** custom SMTP so confirmation and reset emails aren't rate-limited.
3. **Next:** repoint the Lovable web app to the new project (needs Lovable credits) so new shares render on the web; optionally add an AI key secret and deploy `parse-recipe` as a server fallback; custom SMTP for auth emails (the built-in mailer is rate-limited).
4. **Domain:** register `ate.app`, serve `/r/<slug>` on the web, then (paid Apple Developer account) enable Associated Domains with `applinks:ate.app`, host the AASA (template in `docs/associated-domains/`) and set `ATE_SHARE_HOST=https://ate.app`.
5. **Paid account also unlocks:** signed CI builds (already wired with one profile secret per bundle: app, widgets, share, watch, watch widgets), TestFlight, push-to-update Live Activities, Sign in with Apple / CloudKit as options.
6. ✅ **Done in v1.3:** voice cook mode (on-device SFSpeechRecognizer), the "Save to ate" share extension, the aisle-grouped list, the bundled 3-tone chime and haptics, camera capture, JSON-LD import, the tab bar, provenance badges, food-photo guesses, social-link captions, the real logo, Dynamic Type and contrast fixes, the String Catalog, and published legal pages.
6b. **Web share page — live.** Share links are built from `ATE_SHARE_URL_TEMPLATE` (default `https://melusi-k.github.io/ate-legal/r/?s={slug}`; the `?s=` form returns 200, the `/r/<slug>` path 404s before its JS redirect). Incoming links accepted: `ate://recipe/<slug>`, `ate://r/<slug>`, `<host>/r/<slug>` (incl. old lovable.app), `<host>/r/?s=<slug>`.
6c. **Grounded on-device AI (Tier A).** Strict grounding instructions, regional glossary (South/Southern/West African), greedy decoding, model confidence + note on every AI card, Instagram caption prefix stripping, advert-without-dish detection, and a "What dish is this?" step (with suggestions and multi-dish spreads) for generic food photos.
7. **Apple Watch app — built (v1.3).** Independent watchOS 11+ app (`AteWatch`, `com.melusik.ate.watchkitapp`, `WKRunsIndependentlyOfCompanionApp = YES`), embedded in the `.ipa` at `Watch/AteWatch.app`.
   - Recipe list synced straight from Supabase (`user_recipes` over REST, same RLS/auth), with an offline cache.
   - Sign-in on the wrist by email code (Supabase OTP), or session hand-off from a paired, signed-in iPhone via WatchConnectivity.
   - Recipe detail with ingredients; wrist Cook mode with large step text, Next/Back buttons and the Digital Crown, step timers kept alive by `WKExtendedRuntimeSession`, haptics on finish.
   - Smart Stack widget / complication (`AteWatchWidgets`, rectangular, circular, inline) for the running timer.
   - Shopping list with tick-off (last-write-wins upsert).
   - Mirrors the phone's active cook timers via WatchConnectivity when paired.
   - Pure logic in `Shared/Watch/WatchLogic.swift`, unit-tested in `WatchLogicTests`.
   - Limits: Sideloadly/free Apple IDs generally can't install watch apps; use Xcode or a paid account.
8. **Phase: iPad kitchen display.** A landscape `NavigationSplitView` with the library sidebar, the recipe and a full-height cook column. Cook mode becomes a "kitchen display": large-type step, ingredient checklist for that step, and every running timer as a tile grid, with Stage Manager / Split View support. Keyboard shortcuts (→ / ← / space for timer). Always-on with the idle timer disabled while cooking. Pointer and Pencil scribble in the editor.
9. **Phase: foldable / "duo" iPhone layouts.** If Apple ships a foldable iPhone, size-class-driven layouts: folded = the current phone UI; unfolded = a two-pane "duo" layout (recipe on the left, cook step and timers on the right; in the list, aisles on the left and items on the right). Hinge-aware spacing comes from the window geometry, and a book posture puts the step on top with controls below. Build this on adaptive `ViewThatFits` / `horizontalSizeClass` so the iPad work carries over. Verify in the simulator once a device profile exists.

10. **Phase: StoreKit / Ate Plus** (needs paid Apple Developer account). See the "Future phase — StoreKit / Ate Plus" section above.
---

## v1.0 baseline spec

Source: Lovable project **"Ate"** (id `88fe6d64-6eec-4bcb-9f12-7ad3a0c02bbf`), reviewed read-only on 2026-10-10.
Web stack today: TanStack Start (React) + Tailwind/shadcn, localStorage persistence, Supabase (one table), Lovable AI Gateway (Gemini). Published at `recipe-transform-ai.lovable.app`.

---

## 1. Product overview
**ate** (always lowercase in branding) is an AI recipe library. Users paste a **link**, upload a **screenshot**, or type a **prompt**, and ate produces a clean, editable **recipe card** (title, description, servings, time, tags, ingredients, steps with optional timers). Cards are saved **on-device**. From a card the user can scale servings, rewrite it with AI ("make this vegan"), add ingredients to a merged **shopping list**, share a public read-only link, and cook in a big-text **Cook mode** with step timers and alerts.

Tagline: "Turn any link, screenshot or idea into a clean recipe card you can cook from."

### Goals
- Paste-to-card in seconds; user always reviews before saving.
- Offline-first: library, shopping list and cook mode work with no network.
- Privacy: "Private mode" disables all AI calls.

### Non-goals (v1 iOS)
- Accounts/sign-in, cloud sync of the library (web has none).
- Android / iPad-specific layouts (iPhone first; iPad may run scaled).

## 2. Target users
- Home cooks who save recipes from TikTok/Instagram/blogs and want them de-cluttered.
- People who screenshot recipes and lose them in the camera roll.
- Weekly meal planners who need a combined grocery list.
- Hands-busy cooks who want large text and timers at the stove.

## 3. Information architecture & navigation

```
NavigationStack (root = Library)
├── Library  "/"
│   ├── toolbar → Shopping list "/shopping"
│   ├── toolbar → Settings "/settings"
│   ├── row tap → Recipe detail "/recipe/:id"
│   │      ├── Edit (inline toggle on same screen)
│   │      ├── Share → system share sheet (+ public link /r/:slug)
│   │      ├── Delete → back to Library
│   │      └── Cook mode "/cook/:id" (full-screen cover recommended)
│   └── FAB "Add recipe" → Add Recipe sheet (modal)
│          └── Save → push Recipe detail of new card
└── Shared recipe "/r/:slug"  (opened via Universal Link / deep link)
       └── "Save to my library" → Recipe detail of the copy
404 / error states: "Page not found", "Recipe not found", "Nothing to cook here", "This recipe link has expired".
```
iOS: use a single `NavigationStack` with a `Route` enum (`.recipe(id)`, `.cook(id)`, `.shopping`, `.settings`, `.shared(slug)`). Back buttons in web are labelled "Library" / "Exit" / "Open ate" — use these as back titles. Handle `ate://r/<slug>` and `https://recipe-transform-ai.lovable.app/r/<slug>` via `.onOpenURL`.

Toasts (sonner, top-center) → implement a lightweight top toast/banner overlay (success / error).

## 4. Screens

### 4.1 Library (Home) — `/`
**Purpose:** browse and search saved recipes; entry to everything else.
**Layout (max width ~672pt, 16pt side padding, 32pt top, 112pt bottom for FAB):**
- Header row:
  - Left: logo image (`ate-logo.png`, 28×28) + wordmark "ate" (14pt bold, lowercase, letter-spacing 0.2em, primary color). Below: H1 "Your kitchen library" (36pt bold, Fraunces). Subtitle: "{n} recipe(s) saved on this device." (14pt, muted).
  - Right: two ghost icon buttons — ShoppingBasket (→ Shopping), Settings gear (→ Settings). SF Symbols: `basket`, `gearshape`.
- Search field: 48pt tall, fully rounded (capsule), leading magnifier icon, placeholder "Search chicken, pasta, vegan…". Filters case-insensitively across title + description + tags + ingredient names.
- List (12pt spacing) of **RecipeRow** cards (§5.2). Tap → Recipe detail.
- Empty state card (card-surface, centered, 56pt vertical padding): icon UtensilsCrossed (`fork.knife`, primary), title "Nothing saved yet" + "Paste a link or a screenshot and get a clean recipe card in seconds." If recipes exist but none match: "No matches" + "Try another ingredient or tag."
- Floating primary button bottom-center (56pt tall, capsule, 28pt h-padding, float shadow): "+ Add recipe" → presents Add Recipe sheet.
**Data:** all recipes (newest first — new cards are inserted at index 0).

### 4.2 Add Recipe sheet (modal, from Library)
**Purpose:** create a card via AI.
**State 1 — input:**
- Title "Add a recipe" (24pt Fraunces); description "ate turns a link, a screenshot or an idea into a clean recipe card."
- Segmented control, 3 tabs: **Link** (`link`), **Image** (`photo.badge.plus`), **Prompt** (`pencil.line`).
  - Link: text field, placeholder "https://tiktok.com/...", URL keyboard. (iOS: also accept share-extension / paste from clipboard.)
  - Image: dashed-border rounded (12pt) drop zone on muted/50 bg, 32pt padding: "Upload a recipe screenshot" / "Screenshot ready — tap to replace". Use `PhotosPicker` (+ camera optional). Preview image below, max 192pt tall, aspect-fill, rounded 12pt.
  - Prompt: 3-line text editor, placeholder "A quick weeknight miso salmon for two".
- Full-width large primary button: "✨ Generate recipe card"; loading: spinner + "Cooking up your card…" (disabled).
- Validation toasts: Private mode on → "Private mode is on — turn it off in Settings to use AI."; empty link → "Paste a recipe link first."; empty prompt → "Describe the dish first."; no image → "Upload a screenshot first."
**State 2 — review:**
- Title "Review your card"; description "Fix anything the AI got wrong, then save it to your library."
- Shows RecipeCardView (§5.1) or RecipeEditor (§5.3) when editing.
- Buttons row: **Save recipe** (primary, flex) → save, toast "Saved to your library", dismiss, push Recipe detail. **Edit/Preview** toggle (secondary). **Regenerate** (ghost, RefreshCw icon spins while loading).
- Closing the sheet resets all state. `sourceURL` = link when mode is Link.
- Sheet height ≤ 88% screen, scrollable → `.presentationDetents([.large])`.

### 4.3 Recipe detail — `/recipe/:id`
**Purpose:** read, scale, edit, rewrite, share, shop, cook.
- Top bar: back "← Library"; right icon buttons: Share (`square.and.arrow.up`), Edit (`pencil`, toggles edit mode), Delete (`trash`, destructive color) → delete immediately, toast "Recipe deleted", pop to Library. (iOS: add a confirmation dialog — recommended improvement.)
- **Edit mode:** card-surface (20pt padding) with RecipeEditor; every change saves immediately; full-width "Done" button exits edit.
- **View mode:**
  - Servings scaler: three capsule small buttons "x1 servings", "x2 servings", "x3 servings"; selected = primary, others = secondary. Factor multiplies quantities and displayed servings.
  - RecipeCardView with factor.
  - Secondary capsule full-width 48pt button "Add to shopping list" (`list.bullet` + plus) → merges scaled ingredients (source = recipe title), toast "Added to your shopping list".
  - "Ask ate" card: overline label (12–14pt bold uppercase, tracking widest, muted). Text field placeholder "Make this vegan" + primary icon button (sparkles / spinner). Submit on return. Calls AI rewrite, keeps id & createdAt, toast "Recipe updated"; errors shown as toast.
  - Floating bottom-center primary button "Cook mode" (`frying.pan`/chef hat icon) → Cook mode.
- Not found: "Recipe not found" + button "Back to library".
**Share flow:** build plain text (§7.4) for the current factor; call publish to get slug; url = `<host>/r/<slug>`; present `ShareLink`/`UIActivityViewController` with title, text, url. If publish fails, toast "Could not create a share link. Sharing the text instead." and share text only. Fallback copy to clipboard toast "Share link copied to clipboard" / "Recipe copied to clipboard".

### Cooking Tracker — local cooking history

The Insights screen includes a month-based cooking calendar and a consecutive-day streak. The calendar displays every day in the selected month, follows the user's current calendar and time zone, marks today and recorded cooking days distinctly, and lets users navigate to past months but not future months. Selecting a day shows the recipes recorded for that date, with a clear empty state and a fallback label if a recipe has since been deleted.

A cooking event is recorded only when the user reaches the final Cook Mode step and explicitly taps **Finish cooking**. Opening Cook Mode and exiting before that confirmation do not count as a cooked day. The `Recently cooked` collection and Tracker history both update on explicit completion. Multiple completions of the same recipe on one calendar day count as one recipe-day entry. The tracker is local-first and does not request new permissions or sync cooking history in this MVP.

An event is assigned to the device's local calendar day when it is recorded. Stored day keys are stable and are not retroactively rewritten if the user later changes calendar or time zone; that behavior must be made explicit in UI/help rather than silently moving past events. Streaks continue through consecutive stored calendar days; if nothing is recorded today, yesterday's streak remains visible. Calendar and streak tests must cover empty history, today/yesterday, gaps, month/year boundaries, multiple recipes per day, persistence across service instances, and deleted recipes. All date cells and month navigation must have useful VoiceOver labels and remain usable with Dynamic Type.

### 4.4 Cook mode — `/cook/:id`
**Purpose:** hands-free, big-text, step-by-step cooking with timers.
- Full-screen, background **warm**, text warm-foreground, padding 20pt h / 24pt top / 32pt bottom. Keep screen awake (`isIdleTimerDisabled = true`).
- Top: ghost "← Exit" (→ Recipe detail); right "Step {i} of {n}" (14pt medium).
- Progress bar: 6pt tall, capsule track warm-foreground @15%, fill primary, width = (i+1)/n, animated.
- Center (vertically centered, flexible): step instruction, 30pt (34pt on larger) bold Fraunces, line-height snug.
- If step has `timeSeconds`: timer pill (card bg, rounded 16pt, 20×12 padding) with Timer icon (primary) and `m:ss` in 36pt bold monospaced digits; Play/Pause primary capsule button; Reset (`arrow.counterclockwise`) secondary capsule button. Timer resets when step changes. On first play: request notification permission and prime audio.
- On reaching 0: stop, fire `timerFinished("Step {i}", recipeTitle)` (§7.6).
- Bottom: "Back" secondary capsule (56pt, flex 1, disabled on first step); "Next step" primary capsule (flex 2, disabled on last step).
- Empty: "Nothing to cook here" + "Back to library".
- iOS timer must survive backgrounding: store end `Date`, schedule a local `UNNotification` at end time; cancel on pause/reset.
- Product description mentions **voice-controlled step navigation** (not implemented in web code). iOS stretch: `SFSpeechRecognizer` commands "next", "back", "start timer", "pause".

### 4.5 Shopping list — `/shopping`
**Purpose:** one merged grocery list across recipes.
- Back "← Library"; H1 "Shopping list" (30pt bold); subtitle "{pending} to buy · {done} in the basket" (second part only if done>0).
- Add row: capsule 48pt text field "Add something else…" + 48pt round primary "+" button; submit adds a manual item (qty 0, no unit).
- Empty state card: "Nothing on the list" / "Open a recipe and tap “Add to shopping list” — quantities merge automatically."
- List (8pt spacing) of card-surface rows (16×12 padding): checkbox (toggle done), label `"{qty unit} {name}"` (truncated; done = muted + strikethrough), optional caption = source recipe (12pt muted), ghost trash button. Pending items first, then done.
- Export card (when items exist): H2 "Export". Buttons: "Share / copy" (primary → share sheet with list text), "Copy text" (secondary, toast "Copied as text"), ".txt" and ".csv" (secondary → share a file `ate-shopping-list.txt` / `.csv` via share sheet / Files). Second row: ghost "✓ Clear ticked" (disabled if none done), ghost destructive "Clear all" (toast "List cleared").
- Data model supports aisles (Produce, Dairy, Meat & Fish, Pantry, Bakery, Frozen, Other) with keyword guessing (§7.3); web UI doesn't group yet — iOS optional: section by aisle.

### 4.6 Settings — `/settings`
- Back "← Library"; H1 "Settings".
- Card 1: **Private mode** toggle — "Keep everything local — no new AI generations, only your saved cards." (`onDeviceOnly`).
- Card 2: **Timer notifications** — "Choose how ate lets you know a cook-mode step timer has finished." Toggles:
  - Sound — "Play a chime when a timer ends." (default on)
  - Vibration — "Buzz your device (where supported)." (default on) → iOS haptics
  - Step-by-step alerts — "Show a system notification for each step." (default on; turning on requests notification permission)
  - Divider, **Quiet hours** — "Mute the chime during this window — vibration and alerts still work." (default off). When on: two time pickers "From" (default 22:00) and "Until" (07:00), side by side.
- Card 3: **Your data** — "Recipes are stored on this device only. Nothing is uploaded when you browse or cook." Buttons: "Export data" shares a versioned `ate-data.json` archive containing recipes, shopping items, food diary entries and provenance/nutrient snapshots, nutrition goals, local app/timer preferences and export metadata; credentials/session tokens are excluded. "Import data" accepts current archives and legacy recipe-array files. After file selection, confirmation explains that new recipe/shopping/diary items are merged by ID (matching on-device items win) and imported goals/preferences replace current values. Clear local data removes the diary and nutrition goals with the other local data.
- Settings model also has `units: metric|imperial` (default metric) — not exposed in web UI; iOS may add a "Units" segmented picker.

### 4.7 Shared recipe — `/r/:slug`
- Loads row from Supabase `shared_recipes` by slug (public read).
- Back "← Open ate"; RecipeCardView (factor 1); floating primary "Save to my library" (`bookmark` + plus) → copy with new id & createdAt, toast "Saved to your library", navigate to Recipe detail.
- Missing/error: "This recipe link has expired" / "The shared recipe could not be found." + "Open ate".

### 4.8 System states
- 404: "404" (72pt bold), "Page not found", "The page you're looking for doesn't exist or has been moved.", "Go home".
- Error: "This page didn't load", "Something went wrong on our end. You can try refreshing or head back home.", buttons "Try again" / "Go home".

## 5. Shared components

### 5.1 RecipeCardView (props: recipe, factor=1, units=metric)
- card-surface, clipped.
- Header block, bg **warm**, padding 20×24: title 24pt bold (warm-fg); description 14pt warm-fg@80%; meta row: clock "{min} min" (if any), people "{servings×factor} servings"; tags as outline capsule badges.
- Body (padding 20, sections 24 apart):
  - "INGREDIENTS" overline. Rows: fixed 96pt-wide amount column (medium, tabular digits, `formatAmount` after unit conversion) + name, and " — notes" in muted. Each row bottom border (border@60%), 8pt spacing.
  - "STEPS" overline. Numbered rows: 24pt primary circle with white number (12pt bold) + instruction (temperatures converted) + " ({round(sec/60)} min)" muted if timed.

### 5.2 RecipeRowView
card-surface, 16pt padding, 16pt gap, press scale 0.99. Thumbnail 56×56 rounded 16pt (imageURL if http(s), else a generated placeholder seeded from title+tags — iOS: deterministic gradient/emoji tile). Title 18pt semibold single line; description 14pt muted 2 lines; meta 12pt muted: clock min, people servings, first 2 tags as secondary capsule badges.

### 5.3 RecipeEditor (controlled; parent persists)
Fields: Title; Description (2 lines); 2-col Servings (int ≥1) and Total minutes; Tags (comma separated). Ingredients section header with "+ Add" (secondary small): each row = Quantity (80pt number), Unit (80pt, "unit"), Name ("ingredient", flex), trash; Notes full width ("notes (e.g. finely chopped)"). Steps section with "+ Add": instruction (2-line editor), seconds (96pt number, "sec"), trash (re-numbers orders).

## 6. Data models (Swift)
```swift
struct Ingredient: Codable, Hashable { var name: String; var quantity: Double; var unit: String; var notes: String? }
struct Step: Codable, Hashable { var order: Int; var instruction: String; var timeSeconds: Int? }
struct RecipeCard: Codable, Identifiable, Hashable {
  var id: String            // UUID string
  var title: String         // default "Untitled recipe"
  var description: String?
  var servings: Int         // >=1, default 2
  var timeMinutes: Int?
  var tags: [String]
  var ingredients: [Ingredient]
  var steps: [Step]         // order re-numbered 1..n on normalize
  var imageURL: String?
  var sourceURL: String?
  var createdAt: Double     // ms since epoch (keep for JSON compatibility with web export)
}
enum Aisle: String, Codable, CaseIterable { case produce="Produce", dairy="Dairy", meatFish="Meat & Fish", pantry="Pantry", bakery="Bakery", frozen="Frozen", other="Other" }
struct ShoppingItem: Codable, Identifiable { var id: String; var name: String; var quantity: Double; var unit: String; var done: Bool; var from: String?; var sources: [String]?; var notes: String?; var aisle: Aisle? }
struct Settings: Codable { var onDeviceOnly = false; var units: UnitSystem = .metric }
enum UnitSystem: String, Codable { case metric, imperial }
struct TimerPrefs: Codable { var sound = true; var vibration = true; var stepAlerts = true; var quietHours = false; var quietStart = "22:00"; var quietEnd = "07:00" }
```
`normalizeCard`: trim title (fallback "Untitled recipe"), servings = max(1, value or 2), drop empty tags, coerce numbers, renumber steps, defaults for nil.
**Persistence:** web uses localStorage keys `feedme.recipes.v1`, `feedme.settings.v1`, `feedme.shopping.v1`, `feedme.timerprefs.v1`. iOS: JSON files in Application Support (or SwiftData) behind an `@Observable` store; settings/timer prefs in `UserDefaults`/`@AppStorage`. Import/export JSON must be compatible with the web format (array of RecipeCard). Import skips cards with no ingredients and no steps; replaces same-id cards; counts only new ones.

## 7. Business logic to port
### 7.1 Scaling
`quantity × factor`, rounded to 2 decimals; servings shown = round(servings × factor).
### 7.2 Units (`units.ts`)
- Alias table → canonical: g, kg, ml, l, oz, lb, fl oz, cup, tsp, tbsp (with plurals/long names).
- `niceRound`: ≥100 → nearest 5; ≥10 → integer; ≥1 → nearest 0.25; else 2 dp.
- Imperial: g→oz (→lb if ≥16 oz), kg→lb (×2.20462), ml/l→cup if ≥240 ml else fl oz (÷29.5735). Metric: oz/lb→g (→kg if ≥1000), fl oz→ml, cup→ml (×240). Others pass through.
- Temps in text: `(\d{2,3})\s*(°|º|degrees)\s*([CF])` → convert and round to nearest 5.
- `formatUnit`: hide pcs/pc/x/whole/unit(s)/item(s); pluralise clove, piece, can, slice, cup, pinch, bunch, sprig, stick, handful, head, leaf→leaves, tin, packet, jar, fillet, stalk, knob, dash, bottle, bag, sheet, wedge when qty>1 or 0.
- `formatAmount` = "{qty} {unit}" (qty empty when 0).
- `findDurations` regex (e.g. "10 minutes", "1 hr 15 min", "8-10 mins" → upper bound) — available for auto-detecting step timers.
### 7.3 Shopping merge
Merge into an existing **not-done** item when singularised names match and unit families match (mass: g,kg,oz,lb; volume: ml,l,tsp,tbsp,cup,fl oz; count: "",pcs,piece,x,whole; else same unit label). Same unit → add. Different units in a family → convert to base, output g/kg or ml/l (≥1000 → kg/l). Keep the longer name, append source recipe to `sources`, concat notes with "; ". Aisle guessing via keyword regexes (Frozen, Meat & Fish, Dairy, Bakery, Produce, Pantry checked in that order, else Other).
Text export: `ate — shopping list\n\n[ ] 300 g flour (notes)\n[x] …`. CSV header: `item,quantity,unit,notes,aisle,recipe,done`, strings quoted.
### 7.4 Recipe as text (share)
Title; description; "{servings} servings · {min} min"; blank; "Ingredients"; "- {amount} {name} (notes)"; blank; "Steps"; "1. …"; optional "Source: url"; optional share url.
### 7.5 AI parsing (`parseRecipe`)
Input `{mode: url|image|prompt|rewrite, text?, imageDataUrl?, currentRecipe?}` → `{card, source: structured|ai}`.
- url: fetch page (UA "AteBot/1.0", 8s timeout, 400 KB). If schema.org `Recipe` JSON-LD found (incl. `@graph`) → map directly, **no AI call**. Else send stripped page text (≤3500 chars) to AI.
- prompt: "Recipe card for: {text≤500}". image: text + image_url. rewrite: `Rewrite per "{ask}":\n{recipe JSON without id/createdAt/imageURL/sourceURL}`.
- Model chain: `google/gemini-3.6-flash` then `google/gemini-3.1-pro-preview` via `https://ai.gateway.lovable.dev/v1/chat/completions`, `response_format: json_object`, `max_tokens 1600`, with system prompt:
  > Recipe parser. Reply with ONLY minified JSON: {"title":s,"description":s,"servings":i,"timeMinutes":i,"tags":[s],"ingredients":[{"name":s,"quantity":n,"unit":s,"notes":s}],"steps":[{"order":i,"instruction":s,"timeSeconds":i|null}]} Numeric quantities, short units (g,ml,tbsp,cloves,pcs). timeSeconds only for waiting/cooking steps. Keep description under 20 words, steps concise. No prose, no fences.
- Robust JSON extraction with truncation repair. Errors: 429 "Rate limit reached — try again in a moment."; 402 "AI credits exhausted. Add credits to keep cooking."; fallback "AI returned an unreadable recipe. Try again."
- **iOS architecture:** the API key must NOT ship in the app. Options: (a) call the existing published web server function / a Supabase Edge Function `parse-recipe` that wraps this logic (recommended); (b) on-device: Vision `VNRecognizeTextRequest` OCR for screenshots + Apple Foundation Models (iOS 26) for structuring, falling back to the server. The product description explicitly cites "on-device AI and Vision OCR", so (b) is the intended direction with (a) as fallback.
### 7.6 Timer finished
Read prefs; quiet = within quiet window (handles overnight). Sound && !quiet → chime (3 sine tones: 784 Hz, 784 Hz, 1046 Hz at 0/0.28/0.56s) — iOS: bundled chime via AVAudioPlayer / notification sound. Vibration → `UINotificationFeedbackGenerator` / haptic pattern. Step alerts → local notification title "Step {i} is done", body recipe title (time-sensitive interruption level).

## 8. Backend / integrations
> **Current backend (2026-10-11):** Supabase project `ate` (`ploncuhexmwydjxljuhe`, eu-west-1). Schema in `supabase/migrations/`, functions in `supabase/functions/`. `publish-recipe` requires a valid user JWT at the gateway and in the function; anonymous publishing is disabled. It validates the limits below, attributes new rows to `owner_id`, re-sharing an identical card within 10 minutes returns the same slug, and applies per-owner rate limits. Inserts use the service role. `get-shared-recipe?slug=` remains a public read. The Lovable Cloud project `fsowdtisvdctdmjymnpm` is legacy and only used by the web app until it's repointed.
- **Supabase** (project from `.env`; URL + publishable key). Table:
```sql
create table public.shared_recipes (
  slug text primary key, title text not null, description text, image_url text,
  card jsonb not null, created_at timestamptz not null default now(), owner_id uuid references auth.users(id) on delete cascade);
-- RLS: SELECT for anon & authenticated (USING true). Inserts only via service role.
```
- Publish: only a signed-in user can create a share. The server (service role) inserts `{slug: 8-char base36, owner_id, title, description, image_url, card}`; validation limits: title ≤200, description ≤1000, servings 1–200, tags ≤20 (≤60 chars), ingredients ≤100, steps ≤100, instruction ≤2000, urls ≤2000. Read: iOS can query directly with `supabase-swift` + publishable key: `from("shared_recipes").select("slug,title,description,image_url,card").eq("slug", s).maybeSingle()`.
- Share URLs: `https://melusi-k.github.io/ate-legal/r/?s=<slug>` until the production custom domain is live (add Associated Domains for Universal Links later).
- Lovable AI Gateway (server-side only) — see §7.5.
- Auth is Supabase email/password plus magic links; share publishing requires a valid account. No analytics beyond Lovable error reporting (iOS: none / optional crash reporting).

## 9. Visual design
### 9.1 Colors (OKLCH source → sRGB hex approx)
| Token | Light | Dark |
|---|---|---|
| background | `#FCF7ED` (0.977 0.014 84) | `#1A120C` |
| foreground | `#311F16` | `#F3EEE4` |
| card / popover | `#FFFDF7` | `#271D16` |
| primary (terracotta) | `#C95028` (0.585 0.163 38) | `#E77140` |
| primary-foreground | `#FEFAF1` | `#190F0A` |
| secondary | `#F3EAD7` | `#352820` |
| secondary-foreground | `#442C21` | `#F3EEE4` |
| muted | `#F3ECDF` | `#352820` |
| muted-foreground | `#7B675B` | `#ADA397` |
| accent (herb green) | `#4E7F50` | `#5E9660` |
| warm (cook mode / card header) | `#F5E2C0` | `#453421` |
| warm-foreground | `#512E1A` | `#EFE3CF` |
| destructive | `#CC2827` | `#FF6467` |
| border / input | `#E6DDCE` | white @10% / 15% |
| ring | = primary | — |
Theme/status color: `#E2622A`. Implement as an Asset Catalog color set per token with light/dark variants. Default to system appearance.

### 9.2 Typography
- Display (h1–h3, sheet titles, cook-mode step): **Fraunces** (opsz 9–144, weights 500/700), tracking −0.01em. Bundle the font (OFL).
- Body/UI: **DM Sans** 400/500/700. Bundle (OFL).
- Scale used: 36 (library h1), 30 (page h1, cook step), 24 (card title / sheet title), 20 (empty-state h2), 18 (row title, section h2), 16 (base / toggle labels), 14 (body small), 12 (captions, badges). Overlines: bold uppercase, wide tracking (~0.1em). Numbers in amounts/timers: monospaced digits.
### 9.3 Shape, elevation, spacing
- Base radius 16pt (`--radius: 1rem`); sm 12, md 14, lg 16, xl 20, 2xl 24. **card-surface** = card bg + 1pt border + radius 20 + shadow-card (`0 1 2 rgba(brown,0.06)` + `0 12 30 −18 rgba(brown,0.35)`).
- Float shadow on FABs: y 10, blur 30, terracotta @45%.
- Buttons: primary (filled primary), secondary (filled secondary), ghost (transparent), outline; sizes sm/default/lg/icon; many are capsule (`rounded-full`).
- Content max width ~672pt; page padding 16pt; FAB clearance 112pt.
### 9.4 Iconography (lucide → SF Symbols)
Plus→`plus`, Search→`magnifyingglass`, Settings→`gearshape`, ShoppingBasket→`basket`, UtensilsCrossed→`fork.knife`, ArrowLeft→chevron back, ChefHat→`frying.pan`, ListPlus→`text.badge.plus`, Loader2→ProgressView, Pencil→`pencil`, Share2→`square.and.arrow.up`, Sparkles→`sparkles`, Trash2→`trash`, Pause/Play→`pause.fill`/`play.fill`, RotateCcw→`arrow.counterclockwise`, Timer→`timer`, Check→`checkmark`, Copy→`doc.on.doc`, Download→`arrow.down.doc`, Upload→`square.and.arrow.down`, Clock→`clock`, Users→`person.2`, BookmarkPlus→`bookmark`, Link2→`link`, ImagePlus→`photo.badge.plus`, PencilLine→`pencil.line`, RefreshCw→`arrow.clockwise`.
### 9.5 Assets
`src/assets/ate-logo.png` (1024², app logo), `public/icon-192.png`, `icon-512.png` (app icon source), `og-cover.png` (share fallback image). Download from the Lovable project for the asset catalog.

## 10. iOS-specific requirements
- iOS 17+ (iOS 26 for Foundation Models path), SwiftUI, Swift Concurrency, `@Observable` stores.
- Permissions: Photo library (add-image), Notifications, optional Camera, Speech & Microphone (voice cook mode).
- Share extension (stretch): "Save to ate" from Safari/TikTok/Photos → opens Add sheet prefilled.
- Offline: everything except AI generation, rewrite, publish and opening shared links.
- Accessibility: Dynamic Type, VoiceOver labels matching web aria-labels ("Shopping list", "Settings", "Share recipe", "Edit", "Delete", "Remove {item}", etc.), 44pt hit targets.

### 10.1 Widgets, controls & intents ("Widgets & Intents" bundle)
- **One widget extension** (`com.melusik.ate.widgets`, already used by the timer Live Activity) hosts every widget and control, so free Apple IDs spend no extra App ID (5 of the 10/week: app, widgets, share, watch, watch widgets).
- **Data path:** the app writes `WidgetSnapshot` JSON (favourites, next 8 unticked items, tonight's pick with Health state) and the existing `TimerSnapshot` list to the App Group `group.com.melusik.ate` and reloads only the widget kinds whose data changed. Covers are read from the App Group `Covers/` folder and downsampled to 360 px in the extension.
- **Writes from widgets:** timer buttons and the Kitchen timer control are `LiveActivityIntent`s, which the system runs in ate's process when it can (live `TimerCenter`, Live Activity and alerts stay in step); in the extension they edit the App Group copy and reschedule the "timer done" notification themselves. Shopping ticks are queued (`WidgetInbox`, item → wanted state, so repeats are idempotent) and applied when ate becomes active.
- **Widgets:** Cook timers (small/medium + Lock Screen circular ring and rectangular step line), Tonight's pick (small/medium), Shopping list (small/medium/large + Lock Screen inline), Quick add (small), Favourites (medium).
- **Controls (iOS 18 ControlWidget):** Kitchen timer (start 5 min / pause / resume, label shows state), Add to ate. Usable from Control Center, the Lock Screen and the Action button.
- **App Intents:** `RecipeAppEntity` (AppEntity + IndexedEntity, Spotlight), `OpenRecipeIntent`, `StartCookModeIntent`, `AddToShoppingListIntent` (with `GroceryEntity` suggestions so "Add milk to my ate list" is one phrase), `TonightsPickIntent`, `ImportRecipeFromURLIntent`, timer pause/resume/stop, `KitchenTimerIntent`, `QuickAddIntent`, `SearchRecipesIntent` (`.system.search`) and `CreateAteJournalEntryIntent` (`.journal.createEntry`, ate's own journal). App Shortcuts phrases ship with the app (no setup).
- **Deep links:** `ate://open/<id>`, `ate://cook/<id>`, `ate://add/link|photo|prompt`, `ate://shopping`, `ate://timers`. (`ate://recipe/<slug>` stays the shared-recipe link.)
- **Tonight's pick rule:** best `RecipeHealthMatcher` match for the last Health state seen in Insights; otherwise a daily rotation through favourites (or the library); recipes cooked in the last 2 days are skipped when there's another choice.
- **Covers:** user photo → web image → Image Playground (`ImageCreator`, iOS 18.4+, Apple Intelligence) → designed tile; "Generate cover" in the recipe … menu.
- **Free-ID limits:** the widgets depend on the App Group surviving Sideloadly's re-sign; if it doesn't, they show "Open ate" (Settings › Beta testing › Widgets shows App Group status and which widget kinds have loaded). Intents run in the app and are unaffected.

## 11. Acceptance checklist (per screen)
- [ ] Library: search filters live; empty/no-match states; FAB opens sheet.
- [ ] Add sheet: 3 modes, validation toasts, private-mode block, review/edit/regenerate/save.
- [ ] Recipe detail: x1/x2/x3 scaling, edit autosave, Ask ate rewrite, share link, add to list, delete, cook.
- [ ] Cook mode: progress, timers with background notification, back/next bounds, screen stays awake.
- [ ] Shopping: merge logic, manual add, toggle, remove, share/copy/txt/csv, clear ticked/all.
- [ ] Settings: private mode, 4 timer toggles + quiet hours pickers, export/import/clear.
- [ ] Shared recipe: deep link load, expired state, save copy.
