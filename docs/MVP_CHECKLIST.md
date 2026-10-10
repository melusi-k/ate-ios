# ate — MVP-ready checklist (tiered beta / launch gate)

_Rewritten 2026-10-10 against build 36. Scored test matrix: [QA_MATRIX.md](QA_MATRIX.md) · scores: [MVP_SCORE.md](MVP_SCORE.md) · manual steps: [QA.md](QA.md) · tester help: [SUPPORT.md](SUPPORT.md) · [BETA.md](BETA.md)._

**Verdict:** a good candidate for a small **pilot**, but **Tier A is not yet all green**, mainly because nothing has been checked on a real device and builds 35–36 shipped without tests. Not public-launch ready.

**Honesty notes (build 36):** UI tests are optional (`run_tests` workflow input) and have **not** run on the build 35/36 changes. "Pass" in the simulator means the last full run before build 35. Landscape rotation was only enabled in build 36 and is **unverified**. The web share page still reads the **old Lovable backend**.

Legend: ✅ pass (evidence) · 🟡 partial / not re-verified · ❌ not done · ⛔ blocked. Score ✅ = 1, 🟡 = ½, ❌/⛔ = 0. **Launch gates:** Auth (with a real-device gate, A-AUTH-09) and Backend/Share (A-SHARE-*, B-SHARE-01) must be fully ✅ for their tier, whatever the total score.

## Platform constraints

| Constraint | Effect on ate |
|---|---|
| **iOS 18 minimum** (new TabView) | Older iPhones/iOS versions can't install. |
| **Foundation Models needs iOS 26 + Apple Intelligence hardware** (iPhone 15 Pro and later, Apple Intelligence switched on) | Prompt/AI parsing only works there. Otherwise ate falls back to **JSON-LD page data** (links) or a **Demo** card (badged), and OCR/Vision stays on-device. |
| **Free Apple ID sideloading** | Builds expire after **7 days**; testers need **Developer Mode** and to trust the developer profile; limited to about **3 apps / 10 App IDs per week**; **no TestFlight**, **no universal links** (associated domains), **no push-updated Live Activities** (local only). |
| **Unsigned CI builds** | CI produces unsigned `.ipa` files for sideloading (AltStore/Sideloadly/Xcode). The signed path needs a paid account and secrets. |
| **Supabase built-in mailer** | Low hourly email limit (a few per hour) and spam-prone sender, so confirmation/magic-link/reset emails can be delayed or rate-limited. Use custom SMTP before public launch. |

## Tier A — Must-pass before beta (pilot)


### Recipe creation — 3 / 6

- **A-CREATE-01 · Add from link** — ✅
  - *Journey:* As a cook, I paste a recipe blog link and get a card I can save.
  - *Acceptance:* Given a JSON-LD recipe page, When I paste the URL, Then a card with title, ingredients and steps appears in ≤10 s with the "Imported from page data" badge; a dead site fails in ≤10 s with a clear message.
  - *Verified by:* `testQA1_AddFromURL, test02_AddViaLink, JSONLDTests` · QA gate + QA.md §1
  - *Status evidence:* QA1 green in last full run; Instagram caption fixture added in b35 (unit SocialAndPhotoTests)
  - *Owner:* _TBD_

- **A-CREATE-02 · Add from social reel (Instagram/TikTok/YouTube)** — 🟡
  - *Journey:* As a cook, I share a reel and get the recipe from its caption.
  - *Acceptance:* Given a reel with a recipe caption, Then a card is built from the caption; Given no caption, Then a friendly message offers Prompt and switches tabs in one tap.
  - *Verified by:* `testQA1_AddFromURL, test25_InstagramNoCaptionSwitchesToPrompt, testInstagramCaptionFromOG` · QA.md §1
  - *Status evidence:* Caption path verified against the user's reel on the server side; not yet tried in the b35/36 app on a phone
  - *Owner:* _TBD_

- **A-CREATE-03 · Add from photo / screenshot / camera** — 🟡
  - *Journey:* As a cook, I snap or pick a photo and get a recipe.
  - *Acceptance:* Given a recipe screenshot, Then OCR builds a card; Given a text-free food photo, Then "Guessed from photo" or the friendly message appears, never a raw OCR error.
  - *Verified by:* `testQA2_AddFromPhoto, test03_AddViaImage, test20_CameraOptionAndLargeText, testNoFoodMeansNoGuess` · QA.md §2
  - *Status evidence:* Food-photo guessing (VNClassifyImageRequest) is new in b35 and untested on a device
  - *Owner:* _TBD_

- **A-CREATE-04 · Add from prompt (Apple Intelligence)** — 🟡
  - *Journey:* As a cook, I describe a dish and get a recipe.
  - *Acceptance:* Given Apple Intelligence is on, When I submit a prompt, Then a card badged "Made with Apple Intelligence" appears; Given it is off/unsupported, Then a card badged Demo appears and nothing is sent off-device.
  - *Verified by:* `test04_AddViaPromptAndLibraryRow, test24_Provenance` · QA.md §3, §9
  - *Status evidence:* Foundation Models confirmed on the user's iPhone 17 (2026-10-10); fallback never tried on a non-AI device
  - *Owner:* _TBD_

- **A-CREATE-05 · State recovery after interrupted AI generation** — ❌
  - *Journey:* As a cook, I leave the app mid-generation and come back to something sane.
  - *Acceptance:* Given generation is running, When I background the app or lock the phone for 30 s and return, Then either the finished card or a Retry is shown; no endless spinner, no half-saved recipe in the library.
  - *Verified by:* `none` · QA.md (new step)
  - *Status evidence:* No test; no explicit cancellation/resume handling verified
  - *Owner:* _TBD_

- **A-CREATE-06 · Offline while the AI / import route is attempted** — 🟡
  - *Journey:* As a cook, I try to import with no signal and get a clear answer.
  - *Acceptance:* Given airplane mode, When I import a link, Then a friendly offline error with Retry appears in ≤10 s; a prompt still works on-device (Foundation Models needs no network).
  - *Verified by:* `test19_OfflineAndRetry (link only)` · QA.md (new step)
  - *Status evidence:* Link offline path tested; prompt-offline not tested
  - *Owner:* _TBD_


### Edit / save / delete — 3.5 / 5

- **A-EDIT-01 · Review and edit before saving** — ✅
  - *Journey:* As a cook, I fix the AI's mistakes before saving.
  - *Acceptance:* Given a generated card, When I edit title, an ingredient, a step and cuisine, Then the saved recipe shows exactly my edits.
  - *Verified by:* `testQA3_GenerateAndEdit` · QA gate
  - *Status evidence:* QA3 green in last full run
  - *Owner:* _TBD_

- **A-EDIT-02 · Save and survive relaunch / force-close** — 🟡
  - *Journey:* As a cook, I save a recipe and it's still there tomorrow.
  - *Acceptance:* Given I saved a recipe, When I force-close and relaunch, Then it is in the library with identical content.
  - *Verified by:* `testQA4_Save, testPersistence` · QA.md §4
  - *Status evidence:* Persistence unit-tested; force-close on a real device not recorded
  - *Owner:* _TBD_

- **A-EDIT-03 · Inline edit is crash-free** — 🟡
  - *Journey:* As a cook, I edit a saved recipe without the app crashing.
  - *Acceptance:* Given a saved recipe, When I edit every field, add/remove 10 ingredients and steps, rotate, and background mid-edit, Then no crash and the edit persists.
  - *Verified by:* `test05_DetailScaleEditShopDelete` · QA.md (new step)
  - *Status evidence:* Basic edit tested; stress/rotate/background mid-edit not tested; rotation only enabled in b36
  - *Owner:* _TBD_

- **A-EDIT-04 · Delete with clear confirmation and undo** — ✅
  - *Journey:* As a cook, I delete a recipe on purpose, and can undo an accident.
  - *Acceptance:* Given a recipe, When I swipe-delete or use the menu, Then the action is labelled "Delete" in red, an Undo toast shows for ≥4 s, and Undo restores it fully.
  - *Verified by:* `test05_…, test18_SwipeContextMenuPullToRefresh, testStoreMoveAssignsSortIndexAndUndoDelete` · QA.md (new step)
  - *Status evidence:* Undo toast + unit test
  - *Owner:* _TBD_

- **A-EDIT-05 · Safe handling of empty recipe cards** — 🟡
  - *Journey:* As a cook, I never end up with a blank, broken card.
  - *Acceptance:* Given the AI returns no ingredients or steps, Then I see "Couldn't find a recipe" and Save is disabled; a recipe with empty fields still opens without crashing.
  - *Verified by:* `testNoRecipeReturnsNil` · QA.md (new step)
  - *Status evidence:* Parser returns nil for no-recipe; UI handling of a saved empty card not tested
  - *Owner:* _TBD_


### Auth (launch gate) — 2.5 / 9

- **A-AUTH-01 · Sign up + email confirmation** — 🟡
  - *Journey:* As a cook, I create an account and confirm my email.
  - *Acceptance:* Given a new email, When I sign up, Then I see "check your email", and tapping the link opens Ate signed in.
  - *Verified by:* `test15_SignUpPendingAndSignInOut` · QA.md §7 (real device)
  - *Status evidence:* Pending state tested in sim against mock; real-email round trip not recorded on device
  - *Owner:* _TBD_

- **A-AUTH-02 · Weak password and duplicate email** — 🟡
  - *Journey:* As a cook, I get told clearly why sign-up failed.
  - *Acceptance:* Given a <6-char password, Then "at least 6 characters" shows before any network call; Given an existing email, Then "account already exists, sign in instead".
  - *Verified by:* `test12_SignInErrors (partial); Auth.swift weakPassword/userExists` · QA.md (new step)
  - *Status evidence:* Error kinds exist in code; duplicate-email UI not asserted (Supabase may return a fake success for existing emails when confirmation is on)
  - *Owner:* _TBD_

- **A-AUTH-03 · Sign in / sign out (keep vs remove local data)** — 🟡
  - *Journey:* As a cook, I sign out and choose whether my recipes stay on this phone.
  - *Acceptance:* Given signed in, When I choose "keep recipes", Then the library stays; When I choose "remove local data", Then library, shopping list and settings are wiped.
  - *Verified by:* `test15_…, AppStore.signOut(removeLocalData:)` · QA.md §7
  - *Status evidence:* Both buttons exist; remove-data path not asserted by a test
  - *Owner:* _TBD_

- **A-AUTH-04 · Magic link (incl. after reinstall)** — ❌
  - *Journey:* As a cook, I sign in from an email link, even on a fresh install.
  - *Acceptance:* Given I requested a magic link, When I delete and reinstall Ate and then tap the link, Then Ate opens and signs me in (or says the link expired and offers a new one).
  - *Verified by:* `none` · QA.md §7 (real device)
  - *Status evidence:* Never tested on a device
  - *Owner:* _TBD_

- **A-AUTH-05 · Password reset, incl. link opened on another device** — ❌
  - *Journey:* As a cook, I reset my password even if I open the email on my laptop.
  - *Acceptance:* Given a reset email, When I open it on the same iPhone, Then Ate shows set-new-password; When opened on another device, Then a clear page says to open it on the iPhone (no dead end).
  - *Verified by:* `none` · QA.md §7 (real device)
  - *Status evidence:* Cross-device reset untested; depends on redirect URL config
  - *Owner:* _TBD_

- **A-AUTH-06 · Expired session refresh** — 🟡
  - *Journey:* As a cook, I stay signed in for weeks without surprises.
  - *Acceptance:* Given an expired access token with a valid refresh token, Then the next sync refreshes silently; Given both expired, Then a friendly "please sign in again" shows and local data is untouched.
  - *Verified by:* `test30_SessionExpiryAndAccountSwitch, testSessionExpiryMessageIsFriendly` · QA.md (new step)
  - *Status evidence:* Expiry message tested; silent refresh not proven on device
  - *Owner:* _TBD_

- **A-AUTH-07 · Two-device sign-in** — ❌
  - *Journey:* As a cook, I'm signed in on two phones at once.
  - *Acceptance:* Given account X on phones A and B, Then both stay signed in and sync; signing out on A does not sign out B.
  - *Verified by:* `none` · QA.md §7 (real device)
  - *Status evidence:* Needs two devices
  - *Owner:* _TBD_

- **A-AUTH-08 · Delete account** — 🟡
  - *Journey:* As a cook, I delete my account and its data.
  - *Acceptance:* Given signed in, When I delete my account and confirm, Then the auth user and synced rows are gone server-side and I'm signed out.
  - *Verified by:* `test16_DeleteAccount, supabase/functions/delete-account` · QA.md §7
  - *Status evidence:* Mock-tested; real server deletion not verified on device
  - *Owner:* _TBD_

- **A-AUTH-09 · REAL-DEVICE AUTH GATE** — ❌
  - *Journey:* As the developer, I don't ship auth until it works on real phones.
  - *Acceptance:* All of A-AUTH-01…08 pass on iPhone 17 against production Supabase and are recorded in QA_MATRIX.
  - *Verified by:* `—` · QA_MATRIX iPhone 17 column
  - *Status evidence:* Not run
  - *Owner:* _TBD_


### Sync — 3 / 6

- **A-SYNC-01 · Sync recipes across devices** — 🟡
  - *Journey:* As a cook, I edit on one phone and see it on the other.
  - *Acceptance:* Given signed in on A and B, When I edit on A and sync, Then B shows the edit after pull-to-refresh within 10 s.
  - *Verified by:* `testQA7_SyncAccount, testRepeatSyncIsIdempotent` · QA.md §7
  - *Status evidence:* Mock server only; two-phone sync not recorded
  - *Owner:* _TBD_

- **A-SYNC-02 · Sync conflicts (last write wins)** — 🟡
  - *Journey:* As a cook, editing the same recipe on two phones offline doesn't corrupt it.
  - *Acceptance:* Given both phones edit offline, When both sync, Then the newer edit wins entirely and nothing is duplicated.
  - *Verified by:* `testSyncMergeLastWriteWins, testLWWAndTombstones` · QA.md §7
  - *Status evidence:* Unit-tested; not on devices
  - *Owner:* _TBD_

- **A-SYNC-03 · Deletions / tombstones, duplicate IDs, stale references** — 🟡
  - *Journey:* As a cook, deleted recipes stay deleted and nothing doubles up.
  - *Acceptance:* Given a delete on A, Then it disappears on B and never resurrects; repeated syncs never create duplicate IDs; a shopping item pointing at a deleted recipe shows without crashing.
  - *Verified by:* `testLWWAndTombstones, testRepeatSyncIsIdempotent` · QA.md (new step)
  - *Status evidence:* Tombstones/idempotency tested; stale shopping-list references not tested
  - *Owner:* _TBD_

- **A-SYNC-04 · Sync after backgrounding / failure** — ❌
  - *Journey:* As a cook, sync recovers by itself when I come back.
  - *Acceptance:* Given sync failed or the app was backgrounded for >1 h, When I return to the foreground, Then sync retries once, the local library is unchanged on failure, and a non-blocking error shows.
  - *Verified by:* `none (sync failure path only)` · QA.md (new step)
  - *Status evidence:* Foreground-retry not tested
  - *Owner:* _TBD_

- **A-SYNC-05 · Account switching is safe** — ✅
  - *Journey:* As a cook, signing in as someone else never mixes our recipes.
  - *Acceptance:* Given account X's recipes kept locally, When I sign in as Y, Then X's recipes are not uploaded into Y and I'm asked what to do.
  - *Verified by:* `test30_…, testAccountSwitchDetection` · QA.md §7
  - *Status evidence:* Unit + UI test
  - *Owner:* _TBD_

- **A-SYNC-06 · Migration from older local data** — 🟡
  - *Journey:* As a cook, upgrading Ate never loses my library.
  - *Acceptance:* Given a library saved by build 14, When I install the new build over it, Then every recipe opens with its fields, and new fields default sensibly.
  - *Verified by:* `testLegacyRecipeDecodesNewFields, testLegacyRecipeDecodesAsUnknown` · QA.md (new step)
  - *Status evidence:* Decoding tested; real upgrade-in-place on device not done
  - *Owner:* _TBD_


### Share + deep link (launch gate) — 2 / 5

- **A-SHARE-01 · Share a recipe link** — ✅
  - *Journey:* As a cook, I send a recipe to a friend.
  - *Acceptance:* Given a saved recipe, When I tap Share link, Then exactly one link is sent and it resolves on the backend.
  - *Verified by:* `testQA5_Share, test13_ShareOptions` · QA gate
  - *Status evidence:* QA5 green; publish-recipe edge function deployed
  - *Owner:* _TBD_

- **A-SHARE-02 · Open a shared recipe in the app** — 🟡
  - *Journey:* As a friend with Ate, I tap the link and the recipe opens.
  - *Acceptance:* Given `ate://recipe/<slug>`, Then it opens and can be saved; an unknown slug shows "not found".
  - *Verified by:* `testQA6_OpenShared, test09, test10, test14` · QA.md §6
  - *Status evidence:* Simulator only; cross-iPhone not recorded
  - *Owner:* _TBD_

- **A-SHARE-03 · Share link renders on the web** — 🟡
  - *Journey:* As a friend without Ate, I open the link in Safari and see the recipe.
  - *Acceptance:* Given a new share, When opened in any browser, Then the page shows title, ingredients and steps within 3 s.
  - *Verified by:* `none` · Manual
  - *Status evidence:* Resolved for new links (build 4x Tier A): links are now `https://melusi-k.github.io/ate-legal/r/?s=<slug>` (GitHub Pages page reading the new Supabase; returns 200, verified in a browser). Needs a real-device round trip to go ✅. Old lovable.app links still open in the app but not on the web
  - *Owner:* _TBD_

- **A-SHARE-04 · One real share round trip app → web → app** — ⛔
  - *Journey:* As a cook, I share, my friend views it on the web and then opens it in Ate.
  - *Acceptance:* Given a share from phone A, Then the web page renders it AND its "Open in Ate" button opens the recipe on phone B.
  - *Verified by:* `none` · QA.md (new step)
  - *Status evidence:* Web leg unblocked (A-SHARE-03); "Open in ate" uses ate://recipe/<slug>. Universal links still need the paid account (Tier B)
  - *Owner:* _TBD_

- **A-SHARE-05 · Backend unavailable fallback** — 🟡
  - *Journey:* As a cook, a backend outage doesn't break my library.
  - *Acceptance:* Given Supabase unreachable, Then sharing shows a clear error with Retry and everything local still works.
  - *Verified by:* `test19_OfflineAndRetry` · QA.md (new step)
  - *Status evidence:* Offline tested; 5xx-from-backend not tested
  - *Owner:* _TBD_


### Timer reliability — 1 / 3

- **A-TIMER-01 · Timers start / pause / resume / finish** — ✅
  - *Journey:* As a cook, my step timers are exact.
  - *Acceptance:* Given a 1-min timer, Then pause freezes it, resume continues, and finish plays the chime + haptic within 1 s of zero.
  - *Verified by:* `testQA8_Timers, test06, test11_TimerBar` · QA gate
  - *Status evidence:* QA8 green
  - *Owner:* _TBD_

- **A-TIMER-02 · Background / lock with a running timer** — ❌
  - *Journey:* As a cook, I lock my phone and still get told when the pasta's done.
  - *Acceptance:* Given a running timer, When I lock the phone or switch apps for longer than the timer, Then the Lock Screen/Dynamic Island counts down, a notification fires on time, and the in-app time is correct on return (±1 s).
  - *Verified by:* `none on device` · QA.md §8
  - *Status evidence:* Live Activity request asserted in sim only; not recorded on a device
  - *Owner:* _TBD_

- **A-TIMER-03 · Background wake recovery / force-close with a timer** — ❌
  - *Journey:* As a cook, killing the app doesn't lose my timer silently.
  - *Acceptance:* Given a running timer, When iOS kills the app or I force-close it, Then the scheduled notification still fires and on relaunch the timer shows finished or remaining time correctly.
  - *Verified by:* `none` · QA.md (new step)
  - *Status evidence:* Untested
  - *Owner:* _TBD_


### Offline — 1.5 / 2

- **A-OFF-01 · Use the app offline** — ✅
  - *Journey:* As a cook in a kitchen with bad signal, everything local works.
  - *Acceptance:* Given airplane mode, Then browse, search, filter, edit, cook, timers and shopping list all work with no error dialogs.
  - *Verified by:* `test19_OfflineAndRetry` · QA.md (new step)
  - *Status evidence:* Local-first SwiftData
  - *Owner:* _TBD_

- **A-OFF-02 · Retry after network loss** — 🟡
  - *Journey:* As a cook, when signal comes back the failed action works on Retry.
  - *Acceptance:* Given an import/share/sync failed offline, When the network returns and I tap Retry, Then it succeeds without re-entering anything.
  - *Verified by:* `test19_OfflineAndRetry` · QA.md (new step)
  - *Status evidence:* Sim tested; not on device
  - *Owner:* _TBD_


### Reliability — 0.5 / 2

- **A-REL-01 · Launch cleanly, incl. with corrupted local data** — ❌
  - *Journey:* As a cook, Ate always opens.
  - *Acceptance:* Given a corrupted or unreadable local store, Then Ate launches, keeps a backup of the bad file, shows a message, and (if signed in) re-pulls from sync. Cold launch ≤2 s on iPhone 17.
  - *Verified by:* `none` · QA.md (new step)
  - *Status evidence:* No corrupted-store handling verified
  - *Owner:* _TBD_

- **A-NAV-01 · Navigation and layout in portrait and landscape** — 🟡
  - *Journey:* As a cook, I can use Ate held either way.
  - *Acceptance:* Given b36+, When I rotate in the Library, Then landscape shows the sidebar + 2-column grid, portrait shows the list, 4 tabs only, nothing hidden under the tab bar.
  - *Verified by:* `test22_TabBar, test26, test27_LandscapeSidebarGridAndCollections` · QA.md (new step)
  - *Status evidence:* Rotation only just enabled in b36 and unverified; test27 was failing/flaky
  - *Owner:* _TBD_


### Build/test automation — 2 / 4

- **A-CI-01 · CI builds a numbered IPA on every push** — ✅
  - *Journey:* As the developer, every push gives me an installable build.
  - *Acceptance:* Given a push to main, Then `Build IPA` publishes `Ate-<ver>-build<N>.ipa` as a release in ≤10 min.
  - *Verified by:* `Build IPA workflow` · CI
  - *Status evidence:* Builds 35 and 36 published in under 3 min
  - *Owner:* _TBD_

- **A-CI-02 · Unit + key-flow QA tests gate releases** — 🟡
  - *Journey:* As the developer, a broken key flow can't reach testers.
  - *Acceptance:* Given a release candidate, Then AteTests and KeyFlowsQATests pass in CI on the same commit (run with the workflow's run_tests input).
  - *Verified by:* `AteTests, KeyFlowsQATests` · CI
  - *Status evidence:* Tests are OFF by default since b35; b35 and b36 shipped untested
  - *Owner:* _TBD_

- **A-CI-03 · Smoke-test the generated IPA** — ❌
  - *Journey:* As the developer, I know the shipped IPA launches.
  - *Acceptance:* Given the release IPA, When installed on a simulator (CI) and on iPhone 17 (manual), Then it launches to the Library and can add a prompt recipe.
  - *Verified by:* `none` · CI step (to add) + QA.md
  - *Status evidence:* No artifact smoke test
  - *Owner:* _TBD_

- **A-CI-04 · Release artifact integrity** — 🟡
  - *Journey:* As the developer, the IPA I download is the one CI built.
  - *Acceptance:* Given a release, Then it contains a SHA-256 checksum, the bundle includes AteShare + AteWidgets, and version/build in Info.plist match the release name.
  - *Verified by:* `version check step` · CI
  - *Status evidence:* Version check + extension bundling exist; no checksum published
  - *Owner:* _TBD_


### Real-device smoke test — 0 / 1

- **A-DEV-01 · Real-device smoke test of the 8 key flows** — ❌
  - *Journey:* As the developer, I've used the exact build testers get.
  - *Acceptance:* Given the pilot build on iPhone 17, Then all 8 QA.md flows pass and the result is recorded in QA_MATRIX.
  - *Verified by:* `—` · QA.md
  - *Status evidence:* Not run on b35/b36
  - *Owner:* _TBD_


### Pilot readiness — 0.5 / 1

- **A-LAUNCH-01 · Pilot users understand it's beta** — 🟡
  - *Journey:* As a pilot tester, I know Ate is a beta and what to expect.
  - *Acceptance:* Onboarding/About says "Beta"; each tester gets BETA.md + SUPPORT.md (7-day expiry, how to report bugs) before install and confirms they read it.
  - *Verified by:* `—` · docs/BETA.md, docs/SUPPORT.md
  - *Status evidence:* BETA.md + SUPPORT.md exist; testers not invited yet
  - *Owner:* _TBD_


### Apple Health insights — 0 / 8

- **A-HEALTH-01 · No Health prompt at launch** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given a fresh install, When I open Ate, Then no Apple Health permission sheet appears until I tap Connect Apple Health in Insights.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-02 · Read-only, minimal permission** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given I tap Connect Apple Health, Then the sheet lists only sleep, steps, active energy and workouts, all read-only (no write rows).
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-03 · Body state + 3 meal ideas** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given Health has recent data, Then Insights shows a state title (e.g. Recovery day) with reasons and up to 3 saved recipes that fit it; Beta testing → Health insights mock scenarios each show a different state.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-04 · Journal prompt + save locally** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given an insight, When I pick a prompt, write a note and tap Save to journal, Then the entry appears under Your Ate journal and survives relaunch; nothing syncs.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-05 · Graceful denied / unavailable / no-data / unsigned states** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given Health is denied, unavailable, empty or the build lacks the HealthKit entitlement, Then Insights explains what to do with no dead buttons.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-06 · Free-ID sideload keeps Health** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given the latest IPA sideloaded with my free Apple ID, Then Ate installs and Connect Apple Health works on iPhone.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-07 · Journaling Suggestions picker hidden on free ID** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given a free-ID build, Then no Journaling Suggestions button appears (needs the paid entitlement).
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

- **A-HEALTH-08 · Open a suggested recipe and close it** — 🔴
  - *Journey:* As a cook, I get meal ideas that fit how my body is doing today.
  - *Acceptance:* Given a suggested meal in Insights, When I tap it, Then it opens as a sheet and Done returns me to Insights; Cook starts cook mode.
  - *Verified by:* `CoverageUITests` (mock Health) · device
  - *Status evidence:* new in build 59+
  - *Owner:* _TBD_

### Widgets & Intents — 0 / 16

- **A-WIDGET-01 · Cook timers widget: pause / resume / stop** — 🔴
  - *Journey:* As a cook, I control timers from my Home Screen.
  - *Acceptance:* Given a running step timer, When I add the Cook timers widget and tap pause, Then it shows paused within a few seconds, the app shows it paused, and no 'done' alert fires; Stop removes it.
  - *Verified by:* `WidgetLogicTests.testTimerCommands`, `testKitchenToggle` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-WIDGET-02 · Tonight's pick and Favourites open the recipe** — 🔴
  - *Journey:* As a cook, one tap on a widget gets me to a recipe.
  - *Acceptance:* Given Tonight's pick (small/medium) or Favourites (medium, 3–4 covers), When I tap a recipe, Then ate opens on that recipe; Cook on the medium pick opens cook mode.
  - *Verified by:* `WidgetsIntentsUITests.testWidgetDeepLinkOpensRecipe`, `WidgetSnapshotBuilderTests.testPick*` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-WIDGET-03 · Shopping list widget: tick items off** — 🔴
  - *Journey:* As a shopper, I tick items off without opening the app.
  - *Acceptance:* Given 3+ unticked items, When I tap one in the widget, Then it disappears from the widget and is ticked in the app the next time it opens.
  - *Verified by:* `WidgetLogicTests.testInboxDrain`, `AppIntentsTests.testWidgetRelaysActOnLiveStore` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-WIDGET-04 · Quick add widget opens Add recipe** — 🔴
  - *Journey:* As a cook, I add a recipe from my Home Screen in one tap.
  - *Acceptance:* Given the Quick add widget, When I tap Link, Photo or Prompt, Then ate opens on Add recipe with that tab selected.
  - *Verified by:* `WidgetsIntentsUITests.testQuickAddDeepLink` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-WIDGET-05 · Widgets read ate's data on a sideloaded build** — 🔴
  - *Journey:* As a tester, widgets show my data, not a placeholder.
  - *Acceptance:* Given a Sideloadly free-ID install, When I open Beta testing → Widgets, Then it says App Group OK and at least one widget kind loaded; otherwise widgets show “Open ate” and the limitation is noted in BETA.md.
  - *Verified by:* Beta testing → Widgets diagnostics · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-LOCK-01 · Lock Screen circular timer ring** — 🔴
  - *Journey:* As a cook, I glance at the next timer on my Lock Screen.
  - *Acceptance:* Given a running timer, Then the circular accessory shows a countdown ring that empties as it runs, and a pause icon when paused.
  - *Verified by:* device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-LOCK-02 · Lock Screen rectangular step timer** — 🔴
  - *Journey:* As a cook, I see which step is timing.
  - *Acceptance:* Given a running timer, Then the rectangular accessory shows 'Step N · title' and 'mm:ss left' (or 'paused'), and tapping opens cook mode.
  - *Verified by:* `WidgetLogicTests.testStepLineAndFormat` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-LOCK-03 · Lock Screen inline next shopping item** — 🔴
  - *Journey:* As a shopper, the next item sits by the clock.
  - *Acceptance:* Given unticked items, Then the inline accessory shows the next item and how many more; with none it says 'List done'.
  - *Verified by:* `WidgetSnapshotBuilderTests.testSnapshotBuilder` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-CONTROL-01 · Control Center Kitchen timer** — 🔴
  - *Journey:* As a cook, I start or pause a timer from Control Center or the Action button.
  - *Acceptance:* Given no timers, When I tap Kitchen timer, Then a 5-minute timer starts (Live Activity + alert); tapping again pauses it, then resumes it.
  - *Verified by:* `WidgetLogicTests.testKitchenToggle` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-CONTROL-02 · Control Center Quick add** — 🔴
  - *Journey:* As a cook, I add a recipe from Control Center.
  - *Acceptance:* Given the Add to ate control, When I tap it, Then ate opens on Add recipe.
  - *Verified by:* device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-INTENT-01 · Siri: Start cook mode in ate** — 🔴
  - *Journey:* As a cook with messy hands, I start cook mode by voice.
  - *Acceptance:* When I say 'Start cook mode in ate' (or 'Cook Mogodu with ate'), Then ate opens cook mode for that recipe, or tonight's pick when none is named.
  - *Verified by:* `AppIntentsTests.testStartCookMode` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-INTENT-02 · Siri: Add milk to my ate list** — 🔴
  - *Journey:* As a shopper, I add items by voice.
  - *Acceptance:* When I say 'Add milk to my ate list', Then Milk is on the shopping list, without opening ate.
  - *Verified by:* `AppIntentsTests.testAddToShoppingList` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-INTENT-03 · Siri: What's tonight's pick in ate** — 🔴
  - *Journey:* As a cook, I ask what to make tonight.
  - *Acceptance:* When I ask, Then Siri answers with one recipe from my library (and the Health state when Health is connected).
  - *Verified by:* `AppIntentsTests.testTonightsPick` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-INTENT-04 · Search ate from Siri / Spotlight** — 🔴
  - *Journey:* As a cook, I find recipes from Spotlight.
  - *Acceptance:* Given saved recipes, When I search Spotlight for one, Then it appears and opens in ate; 'Search ate for tripe' opens Library filtered by 'tripe'.
  - *Verified by:* `AppIntentsTests.testSearchIntent`, `testRecipeEntityAndQuery` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-INTENT-05 · Siri: save a journal entry in ate** — 🔴
  - *Journey:* As a cook, I add a note to ate's journal by voice.
  - *Acceptance:* When I ask Siri to save a journal entry in ate, Then it appears in Insights → Journal (ate's journal, not Apple's Journal app).
  - *Verified by:* `AppIntentsTests.testJournalEntry` · device (iOS 18.x Apple Intelligence)
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

- **A-COVER-01 · Image Playground covers** — 🔴
  - *Journey:* As a cook, recipes without a photo get a nice cover.
  - *Acceptance:* Given a recipe with no photo or web image on an Apple Intelligence iPhone, Then a Playground cover is generated automatically; 'Generate cover' in the … menu makes a new one; elsewhere the designed tile shows.
  - *Verified by:* `CoverTests` · device
  - *Status evidence:* new in the Widgets & Intents build
  - *Owner:* _TBD_

## Tier B — Before wider/public launch


### Backend/share (launch gate) — 0 / 1

- **B-SHARE-01 · Production share domain (ate.app) + public share page on the new backend** — ⛔
  - *Journey:* As a friend, every Ate link opens on a real domain.
  - *Acceptance:* Given a share, Then the link is https://ate.app/r/<slug> and renders from the new Supabase.
  - *Verified by:* `none` · Manual
  - *Status evidence:* Domain not bought; Lovable page on old backend (Lovable credits). Option: GitHub Pages share page
  - *Owner:* _TBD_


### Apple account path — 0 / 2

- **B-APPLE-01 · Paid Apple Developer account: signing, TestFlight, universal links** — ⛔
  - *Journey:* As a tester, I install from TestFlight and links open Ate.
  - *Acceptance:* Given a paid account, Then CI produces a signed build, uploads to TestFlight, and apple-app-site-association on ate.app makes links open the app.
  - *Verified by:* `signed build path in CI (secrets)` · CI + docs/associated-domains
  - *Status evidence:* Free Apple ID only
  - *Owner:* _TBD_

- **B-APPLE-02 · Signed build validation** — ⛔
  - *Journey:* As the developer, the signed build is valid before upload.
  - *Acceptance:* Given signing secrets, Then `codesign --verify` and entitlement checks pass in CI.
  - *Verified by:* `to add` · CI
  - *Status evidence:* No signing secrets
  - *Owner:* _TBD_


### Full device QA — 1 / 3

- **B-QA-01 · Full QA on real devices across device classes** — ❌
  - *Journey:* As a cook on any supported iPhone, Ate behaves predictably.
  - *Acceptance:* All QA_MATRIX rows pass on iPhone 17 and on an older/non-AI device (e.g. iPhone 13/14 on iOS 18) with Demo/JSON-LD fallbacks clearly labelled.
  - *Verified by:* `—` · QA_MATRIX
  - *Status evidence:* Older device not tested
  - *Owner:* _TBD_

- **B-QA-02 · Accessibility: VoiceOver + largest Dynamic Type + small iPhone** — 🟡
  - *Journey:* As a cook using VoiceOver, I can add and cook a recipe.
  - *Acceptance:* VoiceOver can complete add → save → cook; AX5 text has no clipped controls on iPhone SE/mini size.
  - *Verified by:* `AccessibilityTests, test20` · QA.md
  - *Status evidence:* Unit contrast/font tests; no full VoiceOver pass
  - *Owner:* _TBD_

- **B-QA-03 · Battery/performance with a large library** — 🟡
  - *Journey:* As a cook with 500 recipes, Ate stays fast.
  - *Acceptance:* Given 500 recipes, Then scroll at 60 fps, search/filter ≤200 ms, and a 30-min cook session uses ≤5% battery on iPhone 17.
  - *Verified by:* `testLargeLibraryPerformance` · Unit + manual
  - *Status evidence:* Unit perf test only; no battery measurement
  - *Owner:* _TBD_


### Support — 1.5 / 2

- **B-SUP-01 · Support docs + known-issues list** — ✅
  - *Journey:* As a tester, I can fix the common problems myself.
  - *Acceptance:* SUPPORT.md answers the top 5 issues; BETA.md lists known issues; support can answer each in one message.
  - *Verified by:* `—` · docs/SUPPORT.md, docs/BETA.md
  - *Status evidence:* SUPPORT.md written (this commit)
  - *Owner:* _TBD_

- **B-SUP-02 · Known issues documented and accepted** — 🟡
  - *Journey:* As the developer, every known issue has been consciously accepted for the pilot.
  - *Acceptance:* Each open issue in BETA.md has a severity (P0–P3) and an accept/fix decision; no P0/P1 open.
  - *Verified by:* `—` · docs/BETA.md
  - *Status evidence:* Known limitations listed; severities/acceptance not recorded
  - *Owner:* _TBD_


### Monitoring — 0 / 1

- **B-MON-01 · Crash and retention monitoring** — ❌
  - *Journey:* As the developer, I know when Ate crashes.
  - *Acceptance:* Crash-free sessions measured (TestFlight/Xcode Organizer or Sentry), weekly active testers tracked, privacy policy updated if an SDK is added.
  - *Verified by:* `—` · Dashboard
  - *Status evidence:* No crash reporting; privacy policy currently says no analytics SDKs
  - *Owner:* _TBD_


### Privacy/compliance (launch requirement) — 2 / 4

- **B-PRIV-01 · Privacy policy and terms linked and accurate** — 🟡
  - *Journey:* As a cook, I can read exactly what Ate does with my data.
  - *Acceptance:* Policy and terms reachable from Settings and onboarding; every data flow in the code is described (see audit below).
  - *Verified by:* `—` · docs/legal audit
  - *Status evidence:* Linked and live; audit found mismatches (see Privacy audit)
  - *Owner:* _TBD_

- **B-PRIV-02 · Data deletion confirmation clarity** — 🟡
  - *Journey:* As a cook, I know exactly what's deleted when I delete my account.
  - *Acceptance:* The confirmation lists: account, synced recipes, shopping list; says shared links stay live unless I email; offers to also remove local data; shows a success message.
  - *Verified by:* `test16_DeleteAccount` · QA.md
  - *Status evidence:* Flow exists; copy doesn't cover shared links / local data choice (verify)
  - *Owner:* _TBD_

- **B-PRIV-03 · Privacy manifest, no secrets shipped, AI transparency** — ✅
  - *Journey:* As a cook, Ate is honest about on-device AI and ships no secrets.
  - *Acceptance:* PrivacyInfo.xcprivacy present; only the Supabase publishable key in the bundle; every AI card carries its provenance badge.
  - *Verified by:* `test24_Provenance, secrets scan` · CI + manual
  - *Status evidence:* Repo history scan clean (2026-10-10); provenance badges
  - *Owner:* _TBD_

- **B-PRIV-04 · Legal review** — ❌
  - *Journey:* As the developer, the policy is reviewed before public launch.
  - *Acceptance:* Policy/terms reviewed against POPIA/GDPR and App Store guideline 5.1.
  - *Verified by:* `—` · Sign-off
  - *Status evidence:* Not reviewed
  - *Owner:* _TBD_


## Tier C — Later polish


### Polish — 0 / 6

- **C-POL-01 · Swipe actions on grid cards** — ❌
  - *Journey:* As a cook, I swipe grid cards like list rows.
  - *Acceptance:* Grid cards support the same swipe actions as list rows.
  - *Verified by:* `—` · Manual
  - *Status evidence:* iOS 26 API unconfirmed; long-press menus instead
  - *Owner:* _TBD_

- **C-POL-02 · SwiftData sectionBy grouping** — ❌
  - *Journey:* As a cook, grouped lists scroll smoothly at scale.
  - *Acceptance:* Grouping uses sectionBy where available with identical results.
  - *Verified by:* `LibraryLayoutTests` · Unit
  - *Status evidence:* Grouping works without it
  - *Owner:* _TBD_

- **C-POL-03 · Watch app** — ❌
  - *Journey:* As a cook, I see timers on my wrist.
  - *Acceptance:* Running timers mirror to Apple Watch.
  - *Verified by:* `—` · —
  - *Status evidence:* Not started
  - *Owner:* _TBD_

- **C-POL-04 · iPad and foldable layouts** — ❌
  - *Journey:* As a cook on iPad, I get the sidebar + grid.
  - *Acceptance:* Sidebar/grid used on iPad with no layout breaks.
  - *Verified by:* `—` · —
  - *Status evidence:* Planned phase
  - *Owner:* _TBD_

- **C-POL-05 · Modularise auth/sync/AI/share/timers/deep links** — ❌
  - *Journey:* As the developer, a change in one area can't silently break another.
  - *Acceptance:* Each area is its own module with its own tests.
  - *Verified by:* `—` · —
  - *Status evidence:* PRD v1.3 action 8
  - *Owner:* _TBD_

- **C-POL-06 · Staging Supabase project for end-to-end tests** — ❌
  - *Journey:* As the developer, E2E tests hit a real but separate backend.
  - *Acceptance:* CI runs auth/share/sync E2E against staging when secrets exist.
  - *Verified by:* `—` · CI
  - *Status evidence:* Staging secrets not configured
  - *Owner:* _TBD_

## Privacy-language audit (docs/legal vs code, 2026-10-10)

| # | Policy says | Code does | Fix |
|---|---|---|---|
| P1 | Screenshots are read with Apple's **text recognition** | Also runs **image classification** (`VNClassifyImageRequest`) to guess dishes from food photos, and offers the **camera** | Mention on-device photo classification and camera capture |
| P2 | Only "a single image you choose" + no other access | App requests **microphone + speech recognition** for voice cook mode (on-device only, `requiresOnDeviceRecognition`) | Add a voice-control section: on-device and never recorded |
| P3 | "Your device downloads that web page directly" | Social links also call **Instagram/TikTok/YouTube oEmbed/OG endpoints** with a link-preview user agent, so those services see the request | Name these third parties |
| P4 | "If on-device AI isn't available, ate shows a sample card" | Fallback is **JSON-LD page data** first, then a Demo card | Describe both |
| P5 | Delete account removes "account and synced recipes and shopping list" | Shared recipes remain live (correctly stated elsewhere); the in-app confirmation doesn't say so | Repeat in the in-app delete confirmation (B-PRIV-02) |
| P6 | "No ad or analytics SDKs" | True today. Adding crash reporting (B-MON-01) would make it false | Update the policy in the same change |

No mismatches were found on Supabase EU region, on-device AI (no server `parse-recipe`), sign-out keep/remove local data, or Export data.

## Rollout criteria

**Pilot (5–10 trusted testers, sideloaded):**
- every Tier A item ✅, including A-AUTH-09 (real-device auth gate) and A-DEV-01;
- known issues listed in BETA.md with severities and accepted (B-SUP-02);
- SUPPORT.md shared with testers, and each tester has acknowledged it's a beta;
- the A-SHARE-03/04 blocker is either fixed (e.g. a GitHub Pages share page on the new backend) or explicitly accepted as a known issue for the pilot.

**Public launch:**
- every Tier B item ✅ (ate.app domain + public share page, paid account → signed builds, TestFlight, universal links);
- crash-free sessions **≥ 99.5 %** over **2 weeks** of pilot;
- **no P0/P1** issues open;
- legal review done (B-PRIV-04), with the privacy audit mismatches above fixed;
- App Store / TestFlight submission path working.

