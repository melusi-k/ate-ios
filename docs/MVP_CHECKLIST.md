# ate — MVP-ready checklist (beta gate)

**Verdict (2026-10-10):** a strong MVP candidate for a **controlled beta**, **not public-launch ready**. The remaining gaps are mostly product and infrastructure polish, not core functionality.

Legend: ✅ done (evidence) · 🟡 partial · ❌ not done · ⛔ blocked (reason). "UI" = `AteUITests`, "QA" = `KeyFlowsQATests` (required CI gate), "Unit" = `AteTests`. "Device" = manual check in [QA.md](QA.md). CI = GitHub Actions `Build IPA` on `main`.

Scoring: ✅ = 1, 🟡 = ½, ❌/⛔ = 0. Summary scores live in [MVP_SCORE.md](MVP_SCORE.md) (also appended to every release's notes).

## 1. Core user flows — 11.5 / 12
| # | Item | Status | Evidence / automated test |
|---|---|---|---|
| 1.1 | Add from link | ✅ | QA `testQA1_AddFromURL` (JSON-LD fixture + Instagram caption + fallback); UI `test02_AddViaLink`, `test25_…`; Unit `SocialAndPhotoTests`, JSON-LD tests |
| 1.2 | Add from image | ✅ | QA `testQA2_AddFromPhoto` (screenshot OCR + food-photo path); UI `test03_AddViaImage`, `test20_CameraOptionAndLargeText` |
| 1.3 | Add from prompt | ✅ | UI `test04_AddViaPromptAndLibraryRow`; Foundation Models verified on iPhone 17 (2026-10-10) |
| 1.4 | Review/edit before save | ✅ | QA `testQA3_GenerateAndEdit` |
| 1.5 | Save | ✅ | QA `testQA4_Save` |
| 1.6 | Open | ✅ | UI `test04_…`, `test05_…` |
| 1.7 | Inline edit | ✅ | UI `test05_DetailScaleEditShopDelete`, QA `testQA7` (edit title) |
| 1.8 | Delete | ✅ | UI `test05_…`, `test18_…` (swipe + undo toast); Unit `LibraryLayoutTests` deleteWithUndo |
| 1.9 | Add to shopping list | ✅ | UI `test05_…`, `test07_ShoppingList` (aisle groups) |
| 1.10 | Cook with timers | ✅ | QA `testQA8_Timers`; UI `test06_CookMode`, `test11_TimerBar`, `test21_VoiceCookMode` |
| 1.11 | Share link · open shared from URL | 🟡 | QA `testQA5_Share`, `testQA6_OpenShared`; **web page for new shares ⛔ (Lovable credits — see 5.3)** |
| 1.12 | Offline use | ✅ | UI `test19_OfflineAndRetry`; library is local-first SwiftData |

## 2. Basic UX quality — 6 / 7
| # | Item | Status | Evidence |
|---|---|---|---|
| 2.1 | Empty / error / loading states | ✅ | UI `test01_EmptyLibrary`, `test19_OfflineAndRetry` (ErrorRetryCard), `test10_SharedExpiredAndNotFound` |
| 2.2 | Consistent toasts | ✅ | single `ToastView` (with Undo action); UI `test18_…` |
| 2.3 | Predictable navigation | ✅ | TabView per-tab stacks; UI `test22_TabBar`, `test23_DeepLinkSelectsLibraryTab` |
| 2.4 | Portrait + landscape | ✅ | UI `test27_LandscapeSidebarGridAndCollections` |
| 2.5 | Accessibility labels + Dynamic Type | 🟡 | UI `test20_…` (accessibility XXL), labels on icon buttons; **full VoiceOver pass needs device check** |
| 2.6 | Touch targets ≥ 44 pt | ✅ | `AteButtonStyle` min heights 40–56 + `contentShape`; checked in screenshots |
| 2.7 | No broken layouts | 🟡 | screenshots per CI run (portrait/landscape/XXL); 🟡 until a device pass on a small phone (SE-size) |

## 3. Auth — 8.5 / 9
| # | Item | Status | Evidence |
|---|---|---|---|
| 3.1 | Sign up / sign in | ✅ | UI `test15_SignUpPendingAndSignInOut`, `test12_SignInErrors`; curl-verified against Supabase |
| 3.2 | Magic link | 🟡 | implemented (PKCE); mock-tested; **needs device check** (email → link → app) |
| 3.3 | Password reset | ✅ | implemented + UI flow; device check listed in QA.md |
| 3.4 | Email confirmation | ✅ | UI `test15_…` (pending state + resend); cross-device confirm fallback |
| 3.5 | Sign out | ✅ | UI `test15_…` (keep / remove local data) |
| 3.6 | Delete account | ✅ | UI `test16_DeleteAccount`; `delete-account` edge function (own JWT only) |
| 3.7 | Clear session expiry | ✅ | **new** UI `test30_SessionExpiryAndAccountSwitch`, Unit `testSessionExpiryMessageIsFriendly` — signs out locally, keeps recipes, says so |
| 3.8 | Friendly offline errors | ✅ | UI `test12_SignInErrors` (offline@), `Net.swift` -1005 retry |
| 3.9 | Rate-limit feedback | ✅ | `AuthError.rateLimited` mapping ("Too many emails — try again in an hour"); Supabase mailer is 2/h (Known issue) |

## 4. Sync and data integrity — 8.5 / 9
| # | Item | Status | Evidence |
|---|---|---|---|
| 4.1 | Sync | ✅ | QA `testQA7_SyncAccount` (sign in, edit, sync, 2nd launch pulls); curl-verified (sync-400 fix) |
| 4.2 | Full function signed out | ✅ | every UI test except auth runs signed out |
| 4.3 | Offline handling | ✅ | sync state "failed" with message; local writes queue via stamps |
| 4.4 | Sensible last-write-wins | ✅ | Unit `testLWWAndTombstones` |
| 4.5 | Tombstones safe | ✅ | Unit `testLWWAndTombstones` |
| 4.6 | Local library stable on failure | ✅ | merge only applied after a successful pull; UI `test19_…` |
| 4.7 | Safe account switching | ✅ | **new**: device remembers the last-synced user; switching clears the previous account's copy before pulling. UI `test30_…`, Unit `testAccountSwitchDetection` |
| 4.8 | Idempotent repeat syncs | ✅ | **new** Unit `testRepeatSyncIsIdempotent` — found & fixed a re-push loop from fractional stamps vs bigint rounding |
| 4.9 | Two-device conflicts on real phones | 🟡 | needs device check (QA.md §7) |

## 5. Backend and share stack — 6 / 8
| # | Item | Status | Evidence |
|---|---|---|---|
| 5.1 | Publish | ✅ | `publish-recipe` edge function; curl-verified |
| 5.2 | Retrieve | ✅ | QA `testQA6_OpenShared` (mock); curl against `shared_recipes` |
| 5.3 | Share URL renders on web | ⛔ | Lovable web page still reads the **old Lovable backend**; changing it needs Lovable credits |
| 5.4 | Deep links | 🟡 | `ate://recipe/<slug>` ✅ (UI `test14_…`, QA 6); **universal links ⛔** (paid Apple account + ate.app domain + AASA) |
| 5.5 | Graceful backend-down fallback | ✅ | ErrorRetryCard + offline banner; UI `test19_…` |
| 5.6 | Share host aligned with web app | 🟡 | `ATE_SHARE_HOST` = `recipe-transform-ai.lovable.app` (the web app's host) — aligned on host, but that page reads the old backend (5.3). See note below. |
| 5.7 | Reliable AI parse fallback | ✅ | JSON-LD → social caption → Foundation Models → demo; badges show which. Server fallback = roadmap |
| 5.8 | Clear backend errors | ✅ | PostgREST code/message surfaced in sync status; friendly auth mapping |

**Share-host alignment note:** the app builds links as `${ATE_SHARE_HOST}/r/<slug>` plus `ate://recipe/<slug>`. Both point at the right *host*, and the app reads shares from the new Supabase project. The web page at that host still queries the old Lovable Supabase, so a share made in the iOS app shows "not found" on the web until the page is pointed at the new project (one Lovable edit, blocked on credits) or a static page is hosted elsewhere (e.g. GitHub Pages reading the `get-shared-recipe` function).

## 6. Reliability — 6.5 / 8
| # | Item | Status | Evidence |
|---|---|---|---|
| 6.1 | Clean launch | ✅ | every UI test launches fresh; app launches on iPhone 17 |
| 6.2 | No crashes | 🟡 | none in CI or reported; no crash reporting yet (TestFlight would give it) |
| 6.3 | No data loss after relaunch | ✅ | SwiftData store + QA `testQA7` 2nd launch |
| 6.4 | Timers survive backgrounding | ✅ | end-date timers + Live Activity (QA 8 checks the request hook); device-verified Dynamic Island |
| 6.5 | Offline | ✅ | see 1.12 |
| 6.6 | Large libraries OK | ✅ | **new** Unit `testLargeLibraryPerformance` (500 recipes, all group×sort×filter combos < 3 s, plus `measure`) |
| 6.7 | Search/filter performance | ✅ | same test |
| 6.8 | Older supported iPhones | ❌ | min iOS 18; no iOS 18 / non-AI device tested yet (PRD v1.3 action 6) |

## 7. CI and build — 7 / 7
| # | Item | Status | Evidence |
|---|---|---|---|
| 7.1 | IPA builds | ✅ | every `main` push → `Ate-<ver>-build<N>.ipa` |
| 7.2 | Reliable unit/UI tests | ✅ | unit + UI + QA gate; flaky gestures use accessible fallbacks |
| 7.3 | Correct version metadata | ✅ | CI unzips the .ipa and fails on CFBundleVersion mismatch |
| 7.4 | Consistent artifact naming | ✅ | one versioned asset on `latest-build` + immutable `build-N` |
| 7.5 | Signed path with secrets | ✅ | `BUILD_CERTIFICATE_BASE64` + per-target profiles (README table); unused until a paid account |
| 7.6 | Unsigned sideload path | ✅ | default; Sideloadly instructions |
| 7.7 | Extensions + entitlements in bundle | ✅ | CI verifies `PlugIns/AteWidgets.appex`, `AteShare.appex`, App Group |

## 8. Privacy and compliance — 6 / 6
| # | Item | Status | Evidence |
|---|---|---|---|
| 8.1 | Privacy + terms linked | ✅ | live at melusi-k.github.io/ate-legal; onboarding + Settings; UI `test17_Onboarding`, `test08_Settings` |
| 8.2 | Privacy manifest | ✅ | `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, no tracking) |
| 8.3 | No secrets shipped | ✅ | only the publishable key + URL (public by design); service-role key only in edge functions |
| 8.4 | Data handling documented | ✅ | `docs/legal/privacy.md`; Settings › Your data copy now matches signed-in/out behaviour |
| 8.5 | Clear account deletion | ✅ | see 3.6 |
| 8.6 | AI transparency | ✅ | **new** line in onboarding (`onboardingAITransparency`) and Settings › About (`aiTransparency`); provenance badges |

## 9. Launch gates — 5 / 7
| # | Item | Status | Evidence |
|---|---|---|---|
| 9.1 | Clear onboarding | ✅ | UI `test17_Onboarding` |
| 9.2 | Smooth first run | ✅ | sample-free empty state + add CTA; UI `test01_EmptyLibrary` |
| 9.3 | Critical flows on real devices | 🟡 | AI, timers, sign-in verified on iPhone 17; rest ⛔ manual — QA.md checklist |
| 9.4 | Shared links across real iPhones | ⛔ | needs 5.3 + universal links (paid account + domain) |
| 9.5 | Explicit free-Apple-ID / sideload messaging | ✅ | README, release notes, [BETA.md](BETA.md), in-app beta note |
| 9.6 | Known limitations documented | ✅ | CHANGELOG ⚠️ Known issues, [BETA.md](BETA.md) |
| 9.7 | Beta expectations set | 🟡 | **new** [BETA.md](BETA.md) + Settings › About "What to expect in this beta" (`betaNote`) — ✅ once testers receive it |

## Known non-code blockers
1. **Web share page** reads the old Lovable backend — needs Lovable credits (or a separate static page).
2. **Universal links** — paid Apple Developer account + the ate.app domain + AASA hosting.
3. **Real-device checks** — manual; run [QA.md](QA.md) on at least two iPhones.
