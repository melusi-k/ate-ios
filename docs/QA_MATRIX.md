# ate — QA test matrix (scored)

_Source of truth for IDs and acceptance: [MVP_CHECKLIST.md](MVP_CHECKLIST.md); this matrix and the in-app Beta checks follow it (CI `scripts/check-ids.py`). Current build: 0.1.0 (99). Generated 2026-10-10 against build 36; automated items updated from CI run 38063435067 (build 53, backend-e2e + simulator)._ Items, journeys and acceptance criteria are defined in [MVP_CHECKLIST.md](MVP_CHECKLIST.md); manual steps are in [QA.md](QA.md). Score: ✅ = 1, 🟡 = ½, ❌/⛔ = 0. "Sim result" = last full CI run **before** build 35 (tests have not run since). Fill in the device columns as you test, then update Status._

## Summary

| Tier | Score | % | ✅ | 🟡 | ❌ | ⛔ |
|---|---|---|---|---|---|---|
| Tier A — Must-pass before beta (pilot) | 27 / 44 | 61% | 18 | 18 | 8 | 0 |
| Tier B — Before wider/public launch | 4.5 / 13 | 35% | 2 | 5 | 3 | 3 |
| Tier C — Later polish | 0 / 6 | 0% | 0 | 0 | 6 | 0 |
| **Total** | **31.5 / 63** | **50%** | | | | |

| Tier | Category | Score |
|---|---|---|
| A | Recipe creation | 4 / 6 |
| A | Edit / save / delete | 3.5 / 5 |
| A | Auth (launch gate) | 4.5 / 9 |
| A | Sync | 4.5 / 6 |
| A | Share + deep link (launch gate) | 3.5 / 5 |
| A | Timer reliability | 1 / 3 |
| A | Offline | 1.5 / 2 |
| A | Reliability | 0.5 / 2 |
| A | Build/test automation | 3 / 4 |
| A | Real-device smoke test | 0 / 1 |
| A | Pilot readiness | 0.5 / 1 |
| B | Backend/share (launch gate) | 0 / 1 |
| B | Apple account path | 0 / 2 |
| B | Full device QA | 1 / 3 |
| B | Support | 1.5 / 2 |
| B | Monitoring | 0 / 1 |
| B | Privacy/compliance (launch requirement) | 2 / 4 |
| C | Polish | 0 / 6 |

## Test cases

| ID | Journey | Steps | Expected | Automated test | Sim result | iPhone 17 result | Older/non-AI device result | Status | Notes |
|---|---|---|---|---|---|---|---|---|---|
| A-CREATE-01 | As a cook, I paste a recipe blog link and get a card I can save. | Add › Link › paste URL › Generate | Given a JSON-LD recipe page, When I paste the URL, Then a card with title, ingredients and steps appears in ≤10 s with the "Imported from page data" badge; a dead site fails in ≤10 s with a clear message. | `testQA1_AddFromURL, test02_AddViaLink, JSONLDTests` | Pass (last full run, pre-b35) | Pass (user, b14 era) | Not run | ✅ | QA1 green in last full run; Instagram caption fixture added in b35 (unit SocialAndPhotoTests) |
| A-CREATE-02 | As a cook, I share a reel and get the recipe from its caption. | Add › Link › paste reel URL | Given a reel with a recipe caption, Then a card is built from the caption; Given no caption, Then a friendly message offers Prompt and switches tabs in one tap. | `testQA1_AddFromURL, test25_InstagramNoCaptionSwitchesToPrompt, testInstagramCaptionFromOG` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Caption path verified against the user's reel on the server side; not yet tried in the b35/36 app on a phone |
| A-CREATE-03 | As a cook, I snap or pick a photo and get a recipe. | Add › Image › pick / Camera | Given a recipe screenshot, Then OCR builds a card; Given a text-free food photo, Then "Guessed from photo" or the friendly message appears, never a raw OCR error. | `testQA2_AddFromPhoto, test03_AddViaImage, test20_CameraOptionAndLargeText, testNoFoodMeansNoGuess` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Food-photo guessing (VNClassifyImageRequest) is new in b35 and untested on a device |
| A-CREATE-04 | As a cook, I describe a dish and get a recipe. | Add › Prompt › type › Generate | Given Apple Intelligence is on, When I submit a prompt, Then a card badged "Made with Apple Intelligence" appears; Given it is off/unsupported, Then a card badged Demo appears and nothing is sent off-device. | `test04_AddViaPromptAndLibraryRow, test24_Provenance` | Pass (last full run, pre-b35) | Pass (user) | Not run | 🟡 | Foundation Models confirmed on the user's iPhone 17 (2026-10-10); fallback never tried on a non-AI device |
| A-CREATE-05 | As a cook, I leave the app mid-generation and come back to something sane. | Start a prompt › home-swipe › wait 30 s › reopen | Given generation is running, When I background the app or lock the phone for 30 s and return, Then either the finished card or a Retry is shown; no endless spinner, no half-saved recipe in the library. | `CoverageUITests.test37; SyncFixtureTests.testInterruptedGenerationDraftRoundTrip` | CI pass (b53) | Not run | Not run | ✅ | New DraftStore: app killed mid-generation → 'interrupted, Try again' on relaunch; killed with unsaved card → card restored; saved drafts don't return. |
| A-CREATE-06 | As a cook, I try to import with no signal and get a clear answer. | Airplane mode › Add › Link / Prompt | Given airplane mode, When I import a link, Then a friendly offline error with Retry appears in ≤10 s; a prompt still works on-device (Foundation Models needs no network). | `test19_OfflineAndRetry (link only)` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Link offline path tested; prompt-offline not tested |
| A-EDIT-01 | As a cook, I fix the AI's mistakes before saving. | Review step › edit fields › Save | Given a generated card, When I edit title, an ingredient, a step and cuisine, Then the saved recipe shows exactly my edits. | `testQA3_GenerateAndEdit` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | QA3 green in last full run |
| A-EDIT-02 | As a cook, I save a recipe and it's still there tomorrow. | Save › app switcher swipe-up › reopen | Given I saved a recipe, When I force-close and relaunch, Then it is in the library with identical content. | `testQA4_Save, testPersistence` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Persistence unit-tested; force-close on a real device not recorded |
| A-EDIT-03 | As a cook, I edit a saved recipe without the app crashing. | Detail › Edit › stress steps | Given a saved recipe, When I edit every field, add/remove 10 ingredients and steps, rotate, and background mid-edit, Then no crash and the edit persists. | `test05_DetailScaleEditShopDelete` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Basic edit tested; stress/rotate/background mid-edit not tested; rotation only enabled in b36 |
| A-EDIT-04 | As a cook, I delete a recipe on purpose, and can undo an accident. | Swipe left › Delete › Undo | Given a recipe, When I swipe-delete or use the menu, Then the action is labelled "Delete" in red, an Undo toast shows for ≥4 s, and Undo restores it fully. | `test05_…, test18_SwipeContextMenuPullToRefresh, testStoreMoveAssignsSortIndexAndUndoDelete` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | Undo toast + unit test |
| A-EDIT-05 | As a cook, I never end up with a blank, broken card. | Prompt nonsense › observe; open a recipe with no steps | Given the AI returns no ingredients or steps, Then I see "Couldn't find a recipe" and Save is disabled; a recipe with empty fields still opens without crashing. | `testNoRecipeReturnsNil` | Not run | Not run | Not run | 🟡 | Parser returns nil for no-recipe; UI handling of a saved empty card not tested |
| A-AUTH-01 | As a cook, I create an account and confirm my email. | Settings › Account › Sign up | Given a new email, When I sign up, Then I see "check your email", and tapping the link opens Ate signed in. | `test15_SignUpPendingAndSignInOut` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Pending state tested in sim against mock; real-email round trip not recorded on device |
| A-AUTH-02 | As a cook, I get told clearly why sign-up failed. | Sign up with 123 / an existing email | Given a <6-char password, Then "at least 6 characters" shows before any network call; Given an existing email, Then "account already exists, sign in instead". | `scripts/e2e backend_e2e.py t_auth02; CoverageUITests.test34` | CI pass (b53) | Not run | Not run | ✅ | Server policy verified via GET config/auth (min 8, letters+digits); weak + letters-only rejected (weak_password); duplicate email → identities=[]; UI meter/reason/existing-email prompt covered by test34. Real inbox delivery stays manual. |
| A-AUTH-03 | As a cook, I sign out and choose whether my recipes stay on this phone. | Settings › Account › Sign out (both options) | Given signed in, When I choose "keep recipes", Then the library stays; When I choose "remove local data", Then library, shopping list and settings are wiped. | `test15_…, AppStore.signOut(removeLocalData:)` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Both buttons exist; remove-data path not asserted by a test |
| A-AUTH-04 | As a cook, I sign in from an email link, even on a fresh install. | Request link › reinstall › tap | Given I requested a magic link, When I delete and reinstall Ate and then tap the link, Then Ate opens and signs me in (or says the link expired and offers a new one). | `none` | Not run | Not run | Not run | ❌ | Never tested on a device |
| A-AUTH-05 | As a cook, I reset my password even if I open the email on my laptop. | Forgot password › open link on iPhone and on a laptop | Given a reset email, When I open it on the same iPhone, Then Ate shows set-new-password; When opened on another device, Then a clear page says to open it on the iPhone (no dead end). | `none` | Not run | Not run | Not run | ❌ | Cross-device reset untested; depends on redirect URL config |
| A-AUTH-06 | As a cook, I stay signed in for weeks without surprises. | Force-expire token (debug) › sync | Given an expired access token with a valid refresh token, Then the next sync refreshes silently; Given both expired, Then a friendly "please sign in again" shows and local data is untouched. | `backend_e2e.py t_auth06; CoverageUITests.test38; test30` | CI pass (b53) | Not run | Not run | ✅ | REST refresh_token rotation + refreshed token syncs; mock-auth UI test proves silent refresh before sync; both-expired path in test30. |
| A-AUTH-07 | As a cook, I'm signed in on two phones at once. | Sign in on two phones | Given account X on phones A and B, Then both stay signed in and sync; signing out on A does not sign out B. | `backend_e2e.py t_auth07` | CI pass (b53) | Not run | Not run | ✅ | Two live sessions for one user both push/pull; RLS hides rows from other users. Sign-out-on-A-keeps-B is a device check. |
| A-AUTH-08 | As a cook, I delete my account and its data. | Settings › Delete account | Given signed in, When I delete my account and confirm, Then the auth user and synced rows are gone server-side and I'm signed out. | `test16_DeleteAccount, supabase/functions/delete-account` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Mock-tested; real server deletion not verified on device |
| A-AUTH-09 | As the developer, I don't ship auth until it works on real phones. | Run QA.md §7 on device | All of A-AUTH-01…08 pass on iPhone 17 against production Supabase and are recorded in QA_MATRIX. | `—` | Not run | Not run | Not run | ❌ | Not run |
| A-SYNC-01 | As a cook, I edit on one phone and see it on the other. | Edit on A › pull on B | Given signed in on A and B, When I edit on A and sync, Then B shows the edit after pull-to-refresh within 10 s. | `testQA7_SyncAccount, testRepeatSyncIsIdempotent` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Mock server only; two-phone sync not recorded |
| A-SYNC-02 | As a cook, editing the same recipe on two phones offline doesn't corrupt it. | Airplane both › edit › sync both | Given both phones edit offline, When both sync, Then the newer edit wins entirely and nothing is duplicated. | `backend_e2e.py t_sync; SyncFixtureTests.testMergeFixtures` | CI pass (b53) | Not run | Not run | ✅ | Shared fixtures (AteTests/Fixtures/sync_fixtures.json) run against real Supabase with two clients and in unit tests: LWW by updated_at, convergence, re-sync no-op. |
| A-SYNC-03 | As a cook, deleted recipes stay deleted and nothing doubles up. | Delete on A › sync both × 3 | Given a delete on A, Then it disappears on B and never resurrects; repeated syncs never create duplicate IDs; a shopping item pointing at a deleted recipe shows without crashing. | `backend_e2e.py t_sync; SyncFixtureTests` | CI pass (b53) | Not run | Not run | ✅ | Tombstone propagation, edit-after-delete, idempotent duplicate-ID re-push, stale tombstone refs, in-batch dup ids rejected. |
| A-SYNC-04 | As a cook, sync recovers by itself when I come back. | Background 1 h › reopen; kill network mid-sync | Given sync failed or the app was backgrounded for >1 h, When I return to the foreground, Then sync retries once, the local library is unchanged on failure, and a non-blocking error shows. | `none (sync failure path only)` | Not run | Not run | Not run | ❌ | Foreground-retry not tested |
| A-SYNC-05 | As a cook, signing in as someone else never mixes our recipes. | Sign out (keep) › sign in as Y | Given account X's recipes kept locally, When I sign in as Y, Then X's recipes are not uploaded into Y and I'm asked what to do. | `test30_…, testAccountSwitchDetection` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | Unit + UI test |
| A-SYNC-06 | As a cook, upgrading Ate never loses my library. | Install b14 › add recipes › install new build over it | Given a library saved by build 14, When I install the new build over it, Then every recipe opens with its fields, and new fields default sensibly. | `SyncFixtureTests.testOlderSchemaStoreMigrates` | CI pass (b53) | Not run | Not run | ✅ | Older-schema fixture store (Double servings, no provenance/covers, unknown source, fractional sync stamps) decodes, imports and round-trips. |
| A-SHARE-01 | As a cook, I send a recipe to a friend. | Detail › Share › Share link | Given a saved recipe, When I tap Share link, Then exactly one link is sent and it resolves on the backend. | `testQA5_Share, test13_ShareOptions` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | QA5 green; publish-recipe edge function deployed |
| A-SHARE-02 | As a friend with Ate, I tap the link and the recipe opens. | Tap link on a second iPhone | Given `ate://recipe/<slug>`, Then it opens and can be saved; an unknown slug shows "not found". | `testQA6_OpenShared, test09, test10, test14` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Simulator only; cross-iPhone not recorded |
| A-SHARE-03 | As a friend without Ate, I open the link in Safari and see the recipe. | Open the https link on a laptop | Given a new share, When opened in any browser, Then the page shows title, ingredients and steps within 3 s. | `backend_e2e.py t_share (Playwright)` | CI pass (b53) | Not run | Not run | ✅ | publish-recipe → share page renders title, ingredients, steps (iPhone UA); test share deleted afterwards; http covers dropped. |
| A-SHARE-04 | As a cook, I share, my friend views it on the web and then opens it in Ate. | Share on A › open on web › Open in Ate on B | Given a share from phone A, Then the web page renders it AND its "Open in Ate" button opens the recipe on phone B. | `backend_e2e.py t_share` | CI pass (b53) | Not run | Not run | 🟡 | 'Open in ate' href = ate://recipe/<slug> asserted on the web page; tapping it on a second iPhone is still manual. |
| A-SHARE-05 | As a cook, a backend outage doesn't break my library. | Block network to supabase.co › share | Given Supabase unreachable, Then sharing shows a clear error with Retry and everything local still works. | `CoverageUITests.test36 (-qaBackendDown); test19` | CI pass (b53) | Not run | Not run | ✅ | Forced 503 from AI + sync: ErrorRetryCard shown, retry keeps failing gracefully, library intact. |
| A-TIMER-01 | As a cook, my step timers are exact. | Cook mode › start/pause/resume | Given a 1-min timer, Then pause freezes it, resume continues, and finish plays the chime + haptic within 1 s of zero. | `testQA8_Timers, test06, test11_TimerBar` | Pass (last full run, pre-b35) | Partial (user used cook mode) | Not run | ✅ | QA8 green |
| A-TIMER-02 | As a cook, I lock my phone and still get told when the pasta's done. | Start 2-min timer › lock 3 min | Given a running timer, When I lock the phone or switch apps for longer than the timer, Then the Lock Screen/Dynamic Island counts down, a notification fires on time, and the in-app time is correct on return (±1 s). | `none on device` | Not run | Not run | Not run | ❌ | Live Activity request asserted in sim only; not recorded on a device |
| A-TIMER-03 | As a cook, killing the app doesn't lose my timer silently. | Start timer › force-close › wait › reopen | Given a running timer, When iOS kills the app or I force-close it, Then the scheduled notification still fires and on relaunch the timer shows finished or remaining time correctly. | `none` | Not run | Not run | Not run | ❌ | Untested |
| A-OFF-01 | As a cook in a kitchen with bad signal, everything local works. | Airplane mode › use every tab | Given airplane mode, Then browse, search, filter, edit, cook, timers and shopping list all work with no error dialogs. | `test19_OfflineAndRetry` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | Local-first SwiftData |
| A-OFF-02 | As a cook, when signal comes back the failed action works on Retry. | Fail offline › reconnect › Retry | Given an import/share/sync failed offline, When the network returns and I tap Retry, Then it succeeds without re-entering anything. | `test19_OfflineAndRetry` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Sim tested; not on device |
| A-REL-01 | As a cook, Ate always opens. | Inject a corrupt store (debug) › launch | Given a corrupted or unreadable local store, Then Ate launches, keeps a backup of the bad file, shows a message, and (if signed in) re-pulls from sync. Cold launch ≤2 s on iPhone 17. | `none` | Not run | Not run | Not run | ❌ | No corrupted-store handling verified |
| A-NAV-01 | As a cook, I can use Ate held either way. | Rotate on Library, Detail, Cook | Given the current navigation, When I rotate in the Library, Then landscape shows the sidebar + 2-column grid, portrait shows the list, the main bar has Library, Shopping, Tracker and Settings (plus iOS 26 Search where available), and Beta testing is reachable from Settings. | `test22_TabBar, test26, test27_LandscapeSidebarGridAndCollections` | Not run | Not run | Not run | 🟡 | Rotation only just enabled in b36 and unverified; test27 was failing/flaky |
| A-CI-01 | As the developer, every push gives me an installable build. | Push › check Releases | Given a push to main, Then `Build IPA` publishes `Ate-<ver>-build<N>.ipa` as a release in ≤10 min. | `Build IPA workflow` | n/a | n/a | n/a | ✅ | Builds 35 and 36 published in under 3 min |
| A-CI-02 | As the developer, a broken key flow can't reach testers. | workflow_dispatch with run_tests=true | Given a release candidate, Then AteTests and KeyFlowsQATests pass in CI on the same commit (run with the workflow's run_tests input). | `AteTests, KeyFlowsQATests` | Not run | n/a | n/a | 🟡 | Tests are OFF by default since b35; b35 and b36 shipped untested |
| A-CI-03 | As the developer, I know the shipped IPA launches. | Install artifact › launch | Given the release IPA, When installed on a simulator (CI) and on iPhone 17 (manual), Then it launches to the Library and can add a prompt recipe. | `build-ipa.yml release smoke steps` | CI pass (b53) | Not run | Not run | ✅ | Every build: .ipa plist lint/keys, bundle id, arm64, codesign verify; same commit built for simulator, installed, launched, alive at 10 s, screenshot artifact. |
| A-CI-04 | As the developer, the IPA I download is the one CI built. | Check release assets | Given a release, Then it contains a SHA-256 checksum, the bundle includes AteShare + AteWidgets, and version/build in Info.plist match the release name. | `version check step` | n/a | n/a | n/a | 🟡 | Version check + extension bundling exist; no checksum published |
| A-DEV-01 | As the developer, I've used the exact build testers get. | QA.md §1–8 | Given the pilot build on iPhone 17, Then all 8 QA.md flows pass and the result is recorded in QA_MATRIX. | `—` | n/a | Not run | Not run | ❌ | Not run on b35/b36 |
| A-LAUNCH-01 | As a pilot tester, I know Ate is a beta and what to expect. | Send BETA.md › tester replies | Onboarding/About says "Beta"; each tester gets BETA.md + SUPPORT.md (7-day expiry, how to report bugs) before install and confirms they read it. | `—` | n/a | n/a | n/a | 🟡 | BETA.md + SUPPORT.md exist; testers not invited yet |
| B-SHARE-01 | As a friend, every Ate link opens on a real domain. | Open links on desktop/mobile | Given a share, Then the link is served from the deployed GitHub Pages host and renders from the new Supabase. | `ate-legal` Pages deployment + browser smoke test | Source deployed; browser smoke test pending | Not run | Not run | Not run | 🟡 | `melusi-k.github.io/ate-legal/r/` is deployed and uses `get-shared-recipe`; verify valid share, unknown slug, and retryable function outage before revoking `shared_recipes` SELECT. |
| B-APPLE-01 | As a tester, I install from TestFlight and links open Ate. | — | Given a paid account, Then CI produces a signed build, uploads to TestFlight, and apple-app-site-association on ate.app makes links open the app. | `signed build path in CI (secrets)` | Not run | Not run | Not run | ⛔ | Free Apple ID only |
| B-APPLE-02 | As the developer, the signed build is valid before upload. | — | Given signing secrets, Then `codesign --verify` and entitlement checks pass in CI. | `to add` | n/a | n/a | n/a | ⛔ | No signing secrets |
| B-QA-01 | As a cook on any supported iPhone, Ate behaves predictably. | QA_MATRIX | All QA_MATRIX rows pass on iPhone 17 and on an older/non-AI device (e.g. iPhone 13/14 on iOS 18) with Demo/JSON-LD fallbacks clearly labelled. | `—` | Not run | Not run | Not run | ❌ | Older device not tested |
| B-QA-02 | As a cook using VoiceOver, I can add and cook a recipe. | QA.md §9 | VoiceOver can complete add → save → cook; AX5 text has no clipped controls on iPhone SE/mini size. | `AccessibilityTests, test20` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Unit contrast/font tests; no full VoiceOver pass |
| B-QA-03 | As a cook with 500 recipes, Ate stays fast. | Seed 500 › Instruments | Given 500 recipes, Then scroll at 60 fps, search/filter ≤200 ms, and a 30-min cook session uses ≤5% battery on iPhone 17. | `testLargeLibraryPerformance` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Unit perf test only; no battery measurement |
| B-SUP-01 | As a tester, I can fix the common problems myself. | Read docs | SUPPORT.md answers the top 5 issues; BETA.md lists known issues; support can answer each in one message. | `—` | n/a | n/a | n/a | ✅ | SUPPORT.md written (this commit) |
| B-SUP-02 | As the developer, every known issue has been consciously accepted for the pilot. | Review | Each open issue in BETA.md has a severity (P0–P3) and an accept/fix decision; no P0/P1 open. | `—` | n/a | n/a | n/a | 🟡 | Known limitations listed; severities/acceptance not recorded |
| B-MON-01 | As the developer, I know when Ate crashes. | — | Crash-free sessions measured (TestFlight/Xcode Organizer or Sentry), weekly active testers tracked, privacy policy updated if an SDK is added. | `—` | n/a | n/a | n/a | ❌ | No crash reporting; privacy policy currently says no analytics SDKs |
| B-PRIV-01 | As a cook, I can read exactly what Ate does with my data. | Settings › Privacy | Policy and terms reachable from Settings and onboarding; every data flow in the code is described (see audit below). | `—` | n/a | n/a | n/a | 🟡 | Linked and live; audit found mismatches (see Privacy audit) |
| B-PRIV-02 | As a cook, I know exactly what's deleted when I delete my account. | Settings › Delete account | The confirmation lists: account, synced recipes, shopping list; says shared links stay live unless I email; offers to also remove local data; shows a success message. | `test16_DeleteAccount` | Pass (last full run, pre-b35) | Not run | Not run | 🟡 | Flow exists; copy doesn't cover shared links / local data choice (verify) |
| B-PRIV-03 | As a cook, Ate is honest about on-device AI and ships no secrets. | Inspect IPA | PrivacyInfo.xcprivacy present; only the Supabase publishable key in the bundle; every AI card carries its provenance badge. | `test24_Provenance, secrets scan` | Pass (last full run, pre-b35) | Not run | Not run | ✅ | Repo history scan clean (2026-10-10); provenance badges |
| B-PRIV-04 | As the developer, the policy is reviewed before public launch. | — | Policy/terms reviewed against POPIA/GDPR and App Store guideline 5.1. | `—` | n/a | n/a | n/a | ❌ | Not reviewed |
| C-POL-01 | As a cook, I swipe grid cards like list rows. | — | Grid cards support the same swipe actions as list rows. | `—` | n/a | n/a | n/a | ❌ | iOS 26 API unconfirmed; long-press menus instead |
| C-POL-02 | As a cook, grouped lists scroll smoothly at scale. | — | Grouping uses sectionBy where available with identical results. | `LibraryLayoutTests` | n/a | n/a | n/a | ❌ | Grouping works without it |
| C-POL-03 | As a cook, I see timers on my wrist. | — | Running timers mirror to Apple Watch. | `—` | n/a | n/a | n/a | ❌ | Not started |
| C-POL-04 | As a cook on iPad, I get the sidebar + grid. | — | Sidebar/grid used on iPad with no layout breaks. | `—` | n/a | n/a | n/a | ❌ | Planned phase |
| C-POL-05 | As the developer, a change in one area can't silently break another. | — | Each area is its own module with its own tests. | `—` | n/a | n/a | n/a | ❌ | PRD v1.3 action 8 |
| C-POL-06 | As the developer, E2E tests hit a real but separate backend. | — | CI runs auth/share/sync E2E against staging when secrets exist. | `—` | n/a | n/a | n/a | ❌ | Staging secrets not configured |


### Apple Health insights (v1.4)
- [ ] H-01..H-08 — see PRD "Apple Health insights + Ate journal"

| ID | Scenario (`-qaMockHealth`) | Expect | Automated |
|---|---|---|---|
| H-UI-01 | recovery | "Recovery day", ≤3 protein-led meals, prompt, save → entry; picker hidden | `CoverageUITests.testHealthScenarioRecovery` |
| H-UI-02 | lowEnergy | "Low-energy day", prompt, save → entry | `testHealthScenarioLowEnergy` |
| H-UI-03 | performance | "Good-energy day", prompt, save → entry | `testHealthScenarioPerformance` |
| H-UI-04 | underactive | "Quiet week", prompt | `testHealthScenarioUnderactive` |
| H-UI-05 | recovery vs underactive | Different meal lists | `testHealthSuggestionsDifferByState` |
| H-UI-06 | empty | "No recent Health data" copy | `testHealthScenarioEmpty` |
| H-UI-07 | denied / unavailable / noEntitlement | Graceful copy, no Connect button where it can't work | `testHealthInsightsDeniedAndUnavailable` |
| H-DEV-01 | Beta testing → Health insights picker | Switch scenarios on phone, Insights updates | manual |
| H-DEV-02 | Real Apple Health (free-ID sideload) | Connect sheet lists 4 read types; state renders | manual |
| H-UI-08 | recovery → tap suggestion | Recipe opens as sheet, Done closes back to Insights (A-HEALTH-08) | `testHealthOpenRecipeSheetAndClose` |

Beta-screen IDs: H-UI-01..07 → A-HEALTH-03/04/05/07, H-DEV-01/02 → A-HEALTH-02/03/06.
| H-UI-09 | recovery + `-qaHealthPrompt` | Connect still shows the Health permission prompt | `testHealthPermissionPromptAppearsWhenUndecided` |
| H-UI-10 | empty → Use sample data | Sample data loads Recovery day | `testHealthEmptyStateSampleDataAction` |
| H-UI-11 | `-qaJournalMomentEntry` | Entry shows "From a Journal moment" row; picker never shown | `testJournalMomentContextRow` |
| EXT-JOURNAL-01 | External | Request com.apple.developer.journal.allow (paid team); non-blocking | manual |

## Widgets & Intents (build "Widgets & Intents")

Beta-screen IDs in brackets. Widgets can't be driven by XCUITest, so device checks are manual; logic is unit-tested.

| ID | Setup | Check | Auto |
|---|---|---|---|
| W-01 | Running step timer + Cook timers widget (small/medium) | Countdown ticks; Pause → paused, app agrees, no alert; Resume; Stop removes it [A-WIDGET-01] | `WidgetLogicTests.testTimerCommands`, `AppIntentsTests.testWidgetRelaysActOnLiveStore` |
| W-02 | Tonight's pick small/medium, Favourites medium | Tap opens that recipe; Cook opens cook mode; Health state title shows when Health is connected [A-WIDGET-02] | `WidgetsIntentsUITests.testWidgetDeepLinkOpensRecipe`, `WidgetSnapshotBuilderTests` |
| W-03 | Shopping widget, 3+ items | Tap ticks off; item leaves widget; ticked in app after opening [A-WIDGET-03] | `WidgetLogicTests.testInboxDrain`, `testSnapshotRoundTripAndTick` |
| W-04 | Quick add widget | Link / Photo / Prompt open Add recipe on that tab [A-WIDGET-04] | `WidgetsIntentsUITests.testQuickAddDeepLink` |
| W-05 | Sideloadly free ID | Beta › Widgets: App Group OK, widget kinds loaded; else widgets say "Open ate" [A-WIDGET-05] | `WidgetsIntentsUITests.testBetaPageListsWidgetChecks` (row present) |
| L-01 | Lock Screen circular | Ring empties as the next timer runs; pause icon when paused [A-LOCK-01] | manual |
| L-02 | Lock Screen rectangular | "Step N · title", "mm:ss left"/"paused"; tap opens cook mode [A-LOCK-02] | `WidgetLogicTests.testStepLineAndFormat` |
| L-03 | Lock Screen inline | "Milk · 3 more"; "List done" when empty [A-LOCK-03] | `WidgetSnapshotBuilderTests.testSnapshotBuilder` |
| C-01 | Control Center › Kitchen timer | Start 5 min (Live Activity + alert) → Pause → Resume; label follows [A-CONTROL-01] | `WidgetLogicTests.testKitchenToggle` |
| C-02 | Control Center › Add to ate; Action button | Opens Add recipe [A-CONTROL-02] | manual |
| I-01 | "Start cook mode in ate" / "Cook Mogodu with ate" | Cook mode opens (tonight's pick when unnamed) [A-INTENT-01] | `AppIntentsTests.testStartCookMode` |
| I-02 | "Add milk to my ate list" | Milk on the list, app not opened [A-INTENT-02] | `AppIntentsTests.testAddToShoppingList` |
| I-03 | "What's tonight's pick in ate" | Siri answers with a library recipe [A-INTENT-03] | `AppIntentsTests.testTonightsPick` |
| I-04 | Spotlight "mogodu"; "Search ate for tripe" | Recipe result opens ate; Library filtered [A-INTENT-04] | `AppIntentsTests.testSearchIntent`, `testRecipeEntityAndQuery` |
| I-05 | "Save a journal entry in ate" (Apple Intelligence Siri) | Entry in Insights › Journal [A-INTENT-05] | device |
| P-01 | Recipe without photo on an Apple Intelligence iPhone | Playground cover appears; … › Generate cover replaces it; otherwise designed tile [A-COVER-01] | `CoverTests` |

## Native acceptance (every release)

Run on **iOS 18** (opaque bars) and **iOS 26** (Liquid Glass), in **light** and **dark**. Tick per OS/appearance.

| ID | Check | How | Auto |
|---|---|---|---|
| N-01 | System chrome only | Tab bar, nav bars, Back, menus, search and sheet chrome are system; no custom `glassEffect` (any future use is `#available(iOS 26)` with an opaque iOS 18 fallback). Cards, primary buttons, chips and fields stay opaque. | Review |
| N-02 | Large titles + system Back | Library/Shopping/More/Settings show large serif titles that collapse on scroll; pushed screens have chevron Back and swipe-back; Back never dead from Library, More, Settings or the Insights sheet. | testSystemBackFromRecipeNeverDead |
| N-03 | One bottom area | Recipe detail: Cook mode sits above a single timer bar; Ask Ate scrolls clear; offline strip is at the top. | testBottomBarsDoNotOverlapRecipeDetail |
| N-04 | Search | Library uses system search; query survives tab switches/cancel-and-return; scroll position kept per tab. | test04 |
| N-05 | Destructive actions | Delete recipe, clear list, sign out use a confirmation dialog anchored to the triggering control; delete account is an alert with a safe Cancel. | Manual |
| N-06 | Editing sheets | Add/import sheet has a grabber, Cancel, and won't swipe-dismiss with unsaved input (discard prompt). | Manual |
| N-07 | Filter rail | One non-wrapping row, 44pt chips, selected chip has a checkmark and scrolls into view. | Manual |
| N-08 | AX5 text | Settings › Accessibility › Larger Text at max: every screen readable, nothing clipped, no fixed-size fonts. | testAuditLargestDynamicType (recorded) |
| N-09 | VoiceOver | Every icon button has a spoken label; timers read "4 minutes 12 seconds"; cook steps are headers ("Step 2 of 5. …"); onboarding dots read "Page x of y" and are adjustable; chips announce Selected. | testAuditMainScreens, testAuditOnboarding |
| N-10 | Reduce Motion | Onboarding, progress, list moves and shimmer don't animate. | Manual |
| N-11 | Reduce Transparency | Bars and materials turn opaque; text stays readable. | Manual |
| N-12 | Increase Contrast + Bold Text | Muted text and borders darken; custom fonts get heavier with Bold Text. Brand pairs ≥ 4.5:1 (AccessibilityTests). | AccessibilityTests |
| N-13 | Offline / model unavailable | Typed link/prompt and review drafts are kept; Retry works without retyping. | A-OFF-02 |

### iOS 26 tab bar (build 97+)
| ID | Check | How | Coverage |
|---|---|---|---|
| C-TAB-01 | Add recipe accessory | `.tabViewBottomAccessory` "Add recipe" on every tab opens the Add sheet; no floating button | testTab_AccessoryAndSearchTab, key flows (Add recipe) |
| C-TAB-02 | Timer in accessory | Running timer → timer summary + "+" in the accessory; no duplicate timer bar at tab roots; detail Cook mode clear | testDetailTimerBarLayout (detail), Manual |
| C-TAB-03 | Minimise on scroll | `.tabBarMinimizeBehavior(.onScrollDown)`; accessory compact via `tabViewBottomAccessoryPlacement == .inline` | Manual |
| C-TAB-04 | Search tab | `Tab(role: .search)` + `.searchable`; `.searchPresentationToolbarBehavior(.avoidHidingContent)` keeps "Your Kitchen" | testTab_AccessoryAndSearchTab, test04 |
| C-TAB-05 | Soft scroll edge | `.scrollEdgeEffectStyle(.soft, for: .top)` on Library, Shopping, More, Settings | Manual |
| C-TAB-06 | Concentric cards | `ConcentricRectangle` for cards in the Add/Review sheet | Manual |

## Added from MVP_CHECKLIST (check-ids --fix)

| ID | Journey | Steps | Expected | Automated test | Sim result | iPhone 17 result | Older/non-AI device result | Status | Notes |
|---|---|---|---|---|---|---|---|---|---|
| A-CI-05 | As a cook, docs IDs never drift. | — | CI fails when an item ID exists in MVP_CHECKLIST, QA_MATRIX or the in-app Beta checks but not the others, or when BetaChecklist.swift is stale, or a service-role key appears in the client. | auto `scripts/check-ids.py` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-DATA-01 | As a cook, corrupt store recovers. | — | A broken on-device store is moved to Backups/ate-<timestamp>.store, a fresh store opens, recipes come back from sync when signed in, a 'Library repaired' screen offers a JSON export, and the app never crashes. | auto `StoreRecoveryTests` (corrupt store fixture) | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-DATA-02 | As a cook, save failures are visible. | — | Every SwiftData save goes through StoreSaver: 2 retries, an os_log error, and a non-blocking error banner; on-screen state is kept. | auto `StoreRecoveryTests.testInjectedSaveFailure*` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-HEALTH-01 | As a cook, I get meal ideas that fit how my body is doing today. | — | Given a fresh install, When I open Ate, Then no Apple Health permission sheet appears until I tap Connect Apple Health in Insights. | `CoverageUITests` (mock Health) | Not run | Not run | Not run | 🔴 | new in build 59+ |
| A-HEALTH-04 | As a cook, I get meal ideas that fit how my body is doing today. | — | Given an insight, When I pick a prompt, write a note and tap Save to journal, Then the entry appears under Your Ate journal and survives relaunch; nothing syncs. | `CoverageUITests` (mock Health) | Not run | Not run | Not run | 🔴 | new in build 59+ |
| A-HEALTH-05 | As a cook, I get meal ideas that fit how my body is doing today. | — | Given Health is denied, unavailable, empty or the build lacks the HealthKit entitlement, Then Insights explains what to do with no dead buttons. | `CoverageUITests` (mock Health) | Not run | Not run | Not run | 🔴 | new in build 59+ |
| A-HEALTH-06 | As a cook, I get meal ideas that fit how my body is doing today. | — | Given the latest IPA sideloaded with my free Apple ID, Then Ate installs and Connect Apple Health works on iPhone. | `CoverageUITests` (mock Health) | Not run | Not run | Not run | 🔴 | new in build 59+ |
| A-HEALTH-07 | As a cook, I get meal ideas that fit how my body is doing today. | — | Given a free-ID build, Then no Journaling Suggestions button appears (needs the paid entitlement). | `CoverageUITests` (mock Health) | Not run | Not run | Not run | 🔴 | new in build 59+ |
| A-SEC-01 | As a cook, rLS on every table. | — | Every public table has RLS on; user tables are owner-only (auth.uid() = user_id), no anon policies. | auto backend-e2e `security_checks.t_rls_every_table` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-SEC-02 | As a cook, anon key is read-only for shares. | — | With the anon key, user_recipes and qa_results can't be read or written and shared_recipes can't be inserted directly. | auto backend-e2e `t_anon_denied` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-SEC-03 | As a cook, other users are walled off. | — | Another user's token can't read, update, delete or spoof rows, and users can't write ci QA rows. | auto backend-e2e `t_other_user` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-SEC-04 | As a cook, edge Functions check auth and input. | — | delete-account needs a user JWT; publish-recipe rejects missing/forged auth, bad shapes, overlong and oversized input; get-shared-recipe validates slugs; rate limits respond 429. | auto backend-e2e `t_functions` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-SEC-05 | As a cook, auth settings hardened. | — | Password min 8 with letters+digits, email confirmation on, email OTP ≤ 1 h, leaked-password check reported. | auto backend-e2e `t_auth_settings` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| A-SEC-06 | As a cook, storage, grants and functions reviewed. | — | Storage buckets, anon grants and function search_path are inventoried; open findings land in docs/SECURITY_REVIEW.md. | auto backend-e2e `t_storage_and_functions_sql` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |
| C-AI-01 | As a cook, 80% confidence threshold. | — | A generated card under 80% confidence isn't shown as a recipe: Ate asks 'What dish is this?' pre-filled with its guesses; after you confirm, it regenerates; if still under 80% it shows 'Draft, needs your input' with Save disabled until you edit or confirm. 80%+ skips the question. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-AI-02 | As a cook, main dishes meet the bar. | — | A generated main dish has at least 4 ingredients with quantities, oven steps give °C, and no vague steps like 'cook ribs'; otherwise it's a draft listing what's missing. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-AI-03 | As a cook, tile icons fit the dish. | — | Ribs show a flame (not a teacup), a chicken sandwich shows a takeaway icon (not a bird), drinks show a cup. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-AX-01 | AX5 Larger Text | — | At the largest accessibility text size every screen is readable, nothing is clipped or truncated mid-word, and no fixed-size fonts remain. | auto: detected when the app runs at an accessibility text size + testAuditLargestDynamicType | Not run | Not run | Not run | ❌ | — |
| C-AX-02 | VoiceOver | — | Every icon button has a spoken label; timers read '4 minutes 12 seconds'; cook steps are headers 'Step 2 of 5'; chips announce Selected. | auto: detected when VoiceOver runs + testAuditMainScreens | Not run | Not run | Not run | ❌ | — |
| C-AX-03 | Reduce Motion | — | With Reduce Motion on, onboarding, progress, list moves and shimmer don't animate. | auto: detected when Reduce Motion is on | Not run | Not run | Not run | ❌ | — |
| C-AX-04 | Contrast and Bold Text | — | With Increase Contrast and Bold Text, muted text and borders darken and fonts get heavier; brand colour pairs are ≥4.5:1. | auto: detected when Increase Contrast/Bold Text is on + AccessibilityTests | Not run | Not run | Not run | ❌ | — |
| C-COV-01 | Fallback cover tile | — | A recipe with no image shows the designed plate-and-name tile (never a letter or bird), legible in light and dark mode. | manual | Not run | Not run | Not run | ❌ | — |
| C-COV-02 | Generate cover | — | On an Apple Intelligence iPhone, … › Generate cover makes a new Playground cover in ≤30 s and keeps it after relaunch; elsewhere the option explains why it's unavailable. | auto: mirrors A-COVER-01 | Not run | Not run | Not run | ❌ | — |
| C-COV-03 | Covers everywhere | — | The same cover appears in Library, recipe detail, widgets, Spotlight and Siri cards. | manual | Not run | Not run | Not run | ❌ | — |
| C-DES-01 | Native nav bars | — | Library, Shopping, More and Settings show system large serif titles that collapse on scroll; pushed screens use the system chevron Back and swipe-back; no custom bar chrome. | auto: UI test testSystemBackFromRecipeNeverDead | Not run | Not run | Not run | ❌ | — |
| C-DES-02 | One bottom area on recipe detail | — | Cook mode sits directly above a single timer bar; nothing overlaps the tab bar; Ask Ate scrolls clear; the offline strip is at the top. | auto: UI test testBottomBarsDoNotOverlapRecipeDetail | Not run | Not run | Not run | ❌ | — |
| C-DES-03 | Timer summary bar | — | With 2+ timers running, one compact summary bar shows the soonest timer and '+N more'; tapping it lists all timers with pause/stop. | manual | Not run | Not run | Not run | ❌ | — |
| C-DES-04 | 44 pt tap targets | — | Every button, chip, stepper and icon in Library, recipe detail, cook mode and Settings is at least 44×44 pt. | auto: accessibility audit (hit region) | Not run | Not run | Not run | ❌ | — |
| C-DES-05 | Segmented servings control | — | Servings uses a system segmented/stepper control; changing it rescales every ingredient instantly and VoiceOver reads the value. | manual | Not run | Not run | Not run | ❌ | — |
| C-DES-06 | The … menu | — | The recipe … menu is a system menu with Edit, Share, Generate cover, Add to list and a red Delete last; nothing is clipped or duplicated. | manual | Not run | Not run | Not run | ❌ | — |
| C-DES-07 | Cook mode ✕ | — | Cook mode closes with a top-leading ✕ (labelled 'Close cook mode'); closing with running timers keeps them running and shows them on the timer bar. | manual | Not run | Not run | Not run | ❌ | — |
| C-FIX-01 | As a cook, believable step times. | — | On Nyama yenkomo (and any saved recipe) 'brown beef (2 min)', 'simmer (4 min)', 'pap (3 min)' are gone: implausible AI times show no '(N min)' and no timer, a time written in the step wins, and the card notes that times were corrected. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-02 | As a cook, no empty steps. | — | At 1x, 2x and 3x servings, in detail and cook mode, there are no empty numbered step bubbles. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-03 | As a cook, offline strip below the nav bar. | — | With Wi-Fi and data off, the offline strip sits under the nav bar on Library and recipe detail and never covers the title or back button. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-04 | As a cook, real covers in Siri cards. | — | Tonight's pick and Quick recipes from Shortcuts show the recipe photo, or the designed plate tile, never a bare fork-and-knife. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-05 | As a cook, tidy Spotlight. | — | Searching 'Ate' in Spotlight shows at most 3 'Cook …' suggestions (favourites first) with cover thumbnails, not every recipe. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-06 | As a cook, siri voice diagnostics. | — | Beta › Siri explains whether phrases are registered; after opening Ate once, 'What's tonight's pick in Ate' is tried by voice and the result noted (sideloaded installs may need SideStore/Xcode). | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-07 | As a cook, shopping list as Shortcut output. | — | A Shortcut 'What's on my shopping list' with Show When Run off passes the items as text to the next action (e.g. Show Result), not an empty card. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-FIX-08 | As a cook, one save, one recipe. | — | Saving a card, restoring an unsaved card or tapping Save twice never creates copies; the earlier duplicate 'Ribs and lemon pepper wings' copies are merged into one. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-JRN-01 | Journal entry opens on its own | — | Tapping an entry in Insights › Your Ate journal or More › Journal opens a detail view with the full text, date, state, and any linked recipe, location or media. | auto: detected when an entry detail opens | Not run | Not run | Not run | ❌ | — |
| C-JRN-02 | Journal list with search | — | More › Journal lists every entry newest first; searching by words, place or state filters it, and an empty search says so. | manual | Not run | Not run | Not run | ❌ | — |
| C-JRN-03 | Edit an entry | — | … › Edit opens the text in a sheet; Save updates it and shows 'Edited'; Cancel or swipe-down never loses the original. | auto: detected when an edit is saved | Not run | Not run | Not run | ❌ | — |
| C-JRN-04 | Delete with confirmation | — | … › Delete asks in a confirmation dialog with a safe Cancel; Delete removes the entry and its media and goes back to the list. | auto: detected when a confirmed delete runs | Not run | Not run | Not run | ❌ | — |
| C-JRN-05 | Share an entry | — | Share sends the date, state, text and place as plain text via the share sheet. | manual | Not run | Not run | Not run | ❌ | — |
| C-JRN-06 | Shortcuts Open journal entry | — | The 'Open journal entry' action in Shortcuts lets me pick an entry and opens its detail view in Ate; a deleted entry gives a clear error. | auto: detected when the intent opens an entry | Not run | Not run | Not run | ❌ | — |
| C-JRN-07 | Location and media from Siri/Shortcuts | — | 'New journal entry' with a Location and Media Items saves them; the entry detail shows the place (with a map) and the photos. | manual | Not run | Not run | Not run | ❌ | — |
| C-JRN-08 | Image prompts are never journal entries | — | Sending an image-generation prompt (e.g. 'A top-down, highly detailed photograph…') to New journal entry is refused with a clear message, and old ones are cleaned up. | auto: JournalTextGuardTests | Not run | Not run | Not run | ❌ | — |
| C-LIB-01 | As a cook, library header. | — | Library shows the logo in the toolbar, the native large title 'Your Kitchen', 'Search N recipes' in the search bar, a quiet count, and one icon-only Group & sort menu that never truncates. | `—` | Not run | Not run | Not run | ❌ | Build 97; awaiting device run |
| C-NAT-01 | N-01 System chrome only | — | Tab bar, nav bars, Back, menus, search and sheet chrome are system; no custom glassEffect without an opaque iOS 18 fallback; cards, buttons, chips and fields stay opaque. | manual | Not run | Not run | Not run | ❌ | — |
| C-NAT-02 | N-02 Large titles + system Back | — | Large serif titles collapse on scroll; pushed screens have chevron Back and swipe-back; Back is never dead from Library, More, Settings or the Insights sheet. | auto: UI test | Not run | Not run | Not run | ❌ | — |
| C-NAT-03 | N-03 One bottom area | — | Recipe detail: Cook mode above a single timer bar; Ask Ate scrolls clear; offline strip at the top. | auto: UI test | Not run | Not run | Not run | ❌ | — |
| C-NAT-04 | N-04 Search | — | Library uses system search; the query survives tab switches and cancel-and-return; scroll position is kept per tab. | auto: UI test test04 | Not run | Not run | Not run | ❌ | — |
| C-NAT-05 | N-05 Destructive actions | — | Delete recipe, clear list and sign out use a confirmation dialog anchored to the control; delete account is an alert with a safe Cancel. | manual | Not run | Not run | Not run | ❌ | — |
| C-NAT-06 | N-06 Editing sheets | — | The add/import sheet has a grabber and Cancel, and won't swipe-dismiss with unsaved input (discard prompt). | manual | Not run | Not run | Not run | ❌ | — |
| C-NAT-07 | N-07 Filter rail | — | One non-wrapping row of 44 pt chips; the selected chip has a checkmark and scrolls into view. | manual | Not run | Not run | Not run | ❌ | — |
| C-NAT-08 | N-08 AX5 text | — | At max Larger Text every screen is readable with nothing clipped. | auto: same detection as C-AX-01 | Not run | Not run | Not run | ❌ | — |
| C-NAT-09 | N-09 VoiceOver | — | Icon buttons labelled; timers spoken in words; steps are headers; onboarding dots read 'Page x of y' and are adjustable. | auto: same detection as C-AX-02 | Not run | Not run | Not run | ❌ | — |
| C-NAT-10 | N-10 Reduce Motion | — | Onboarding, progress, list moves and shimmer don't animate. | auto: same detection as C-AX-03 | Not run | Not run | Not run | ❌ | — |
| C-NAT-11 | N-11 Reduce Transparency | — | Bars and materials turn opaque and text stays readable. | auto: detected when Reduce Transparency is on | Not run | Not run | Not run | ❌ | — |
| C-NAT-12 | N-12 Increase Contrast + Bold Text | — | Muted text and borders darken; custom fonts get heavier with Bold Text. | auto: same detection as C-AX-04 | Not run | Not run | Not run | ❌ | — |
| C-NAT-13 | N-13 Offline / model unavailable | — | Typed link/prompt and review drafts are kept offline; Retry works without retyping. | auto: mirrors A-OFF-02 | Not run | Not run | Not run | ❌ | — |
| C-SIRI-01 | Phrases recognised by voice | — | 'Cook Mogodu in Ate', 'What's tonight's pick in Ate' and 'What's on my Ate shopping list' are all handled by Ate by voice, not a web answer; Beta › Siri lists the registered phrases. | auto: registered phrases detected | Not run | Not run | Not run | ❌ | — |
| C-SIRI-02 | Clean Siri dialog | — | Every Siri reply starts with a capital, has no stray spaces before punctuation, and is never blank. | auto: SiriPolishTests | Not run | Not run | Not run | ❌ | — |
| C-SIRI-03 | Snippet cards show covers | — | Tonight's pick, Quick recipes and timer cards show the recipe cover, not a generic icon, with working buttons. | manual | Not run | Not run | Not run | ❌ | — |
| C-SIRI-04 | Fuzzy recipe names | — | 'Cook Mugod' finds Mogodu, ambiguous names ask which one, unknown names say so, and the wrong recipe is never started. | auto: SiriRoutingTests | Not run | Not run | Not run | ❌ | — |
| C-WID-01 | Widgets read live data | — | Beta testing › Widgets says App Group OK and at least one widget kind has loaded; no widget is stuck on 'Open ate'. | auto: App Group + widget heartbeat detected | Not run | Not run | Not run | ❌ | — |
| C-WID-02 | Widget gallery polish | — | All five Ate widgets appear in the gallery with names, descriptions and correct previews in light, dark and tinted modes. | manual | Not run | Not run | Not run | ❌ | — |
| C-WID-03 | Lock Screen accessories | — | Circular ring, rectangular step timer and inline shopping item render legibly in every Lock Screen font/colour and update within a few seconds. | manual | Not run | Not run | Not run | ❌ | — |
| C-WID-04 | Control Center controls | — | Kitchen timer and Quick add appear in the Controls gallery with icons and labels, and work from the Lock Screen and Action button. | manual | Not run | Not run | Not run | ❌ | — |

## Added from MVP_CHECKLIST (check-ids --fix)

| ID | Journey | Steps | Expected | Automated test | Sim result | iPhone 17 result | Older/non-AI device result | Status | Notes |
|---|---|---|---|---|---|---|---|---|---|
| A-CI-06 | As a cook, published IPA verified. | — | Each release publishes <ipa>.sha256 and the SHA-256 in the notes; the smoke step downloads the published asset, verifies the checksum, version/build, bundle ID, extensions (widgets, watch), entitlements, privacy manifest, app icon and size limits, and withdraws the release on failure. | auto `scripts/verify-ipa.sh` | Not run | Not run | Not run | ❌ | Added build 97; first CI run pending |


## Cooking Tracker focused acceptance (issue #31)

| Area | Acceptance / expected behavior | Evidence required | Status |
|---|---|---|---|
| Calendar month | Shows every date in the displayed month with weekday alignment, leading/trailing empty cells, a distinct today marker, and cooked-day markers. Month title always matches the visible dates. | Simulator UI test + visual check | Pending |
| Month navigation | Previous/next month controls work; future months cannot be selected. Navigating months clears an out-of-month selected day. | Simulator UI test | Pending |
| Selected day | Tapping a date opens that date's details; empty dates explain that nothing was recorded; missing/deleted recipes have a fallback label. | Simulator UI test | Pending |
| History persistence | Local event history survives service re-instantiation/relaunch and uses isolated test storage. | Unit tests | Partial — persistence unit test added; relaunch/device evidence pending |
| Streak rules | Empty history, today, yesterday, gaps, month/year boundaries, and multiple recipes in one day are deterministic. | Unit tests | Partial — core today/yesterday/gap cases covered; boundary cases pending |
| Calendar/time-zone change | Historical events stay assigned to the local day key captured at record time; changing device time zone/calendar must not silently rewrite history. | Unit test + device setting-change check | Pending |
| Accessibility | Month controls and dates have descriptive labels, selected state is exposed, weekday decoration is hidden from VoiceOver, and layout remains usable at larger text sizes. | VoiceOver + Dynamic Type device QA | Pending |

This section supplements the canonical IDs in `MVP_CHECKLIST.md`; do not mark the tracker complete until automated and device evidence is attached to [issue #31](https://github.com/melusi-k/ate-ios/issues/31).
