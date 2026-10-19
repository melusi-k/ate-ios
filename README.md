# ate — iOS

Native SwiftUI (iOS 18+, iPhone; Apple Intelligence features need iOS 26 on supported hardware) rebuild of the **ate** AI recipe library. Full spec: [docs/PRD.md](docs/PRD.md).

**Beta / launch gate:** [docs/MVP_CHECKLIST.md](docs/MVP_CHECKLIST.md) (tiered A/B/C, score in [docs/MVP_SCORE.md](docs/MVP_SCORE.md), test matrix [docs/QA_MATRIX.md](docs/QA_MATRIX.md)) · **Support FAQ:** [docs/SUPPORT.md](docs/SUPPORT.md) · **QA gate:** [docs/QA.md](docs/QA.md) — the full test matrix is required for `latest-beta` promotion; ordinary `latest-build` releases run smoke checks but not the full suite by default · Testers: [docs/BETA.md](docs/BETA.md).

## Features

**Production polish:** the shipped tab bar contains Library, Shopping, Tracker, Settings, and (on iOS 26) Search. There is no More/Beta tab. The Beta testing screen and its launch banner are compiled into the app but are shown only when the embedded build channel is an allow-listed beta channel (TierA/TierB/TierC/Beta/QA/Internal/Development). Empty, unknown, and `Production` channels fail closed; `project.yml` defaults to an empty channel. CI beta builds explicitly set `TierA` by default.
Library + search · Add recipe sheet (Link / Image / Prompt → review/edit/regenerate/save) · Recipe detail (x1/x2/x3 scaling, inline edit, Ask ate rewrite, share, add to shopping list, delete) · Cook mode (big text, progress, step timers with background notifications, screen stays awake; explicit Finish cooking records a Tracker day) · Cooking Tracker (local-only month calendar, selected-day recipes, completion streak) · Shopping list (merge, manual add, tick, share/copy/.txt/.csv, clear) · Settings (private mode, units, timer prefs + quiet hours, export/import/clear) · Shared recipe deep links (`ate://recipe/<slug>`, legacy `ate://r/<slug>`) · 404 / error states.

Also: Journal, widgets / Lock Screen / Control Center, Siri & Shortcuts, Apple Watch timers, iOS 26 tab bar (Library, Shopping, Tracker, Settings, Search, Add recipe accessory). Beta diagnostics are available only in explicitly named beta build channels; production builds hide both the Beta testing entry and beta banner.

Data is stored on-device with SwiftData. A corrupt store is moved to `Backups/` and rebuilt from sync with a JSON export (A-DATA-01); failed saves retry and show a banner (A-DATA-02). Settings live in UserDefaults.

**Docs are one source of truth:** item IDs and statuses are defined in `docs/MVP_CHECKLIST.md`; `docs/QA_MATRIX.md` and the in-app Beta checks (`Ate/Logic/BetaChecklist.swift`, generated) follow it, and `scripts/check-ids.py` fails CI on drift (A-CI-05). Security: [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md).

## AI
- **Default: on-device.** Apple Foundation Models (`LanguageModelSession` + `@Generable` recipe type) on iOS 26+ devices with Apple Intelligence. Screenshots go through Vision OCR (`VNRecognizeTextRequest`). For links, the app fetches the page and passes its text to the model.
- If the system model isn't available (older iOS, unsupported device, Apple Intelligence off), links with schema.org page data still import via JSON-LD; everything else **falls back to demo cards** badged "Demo". The Add sheet and Settings show which one is active.
- Everything goes through the `BackendService` protocol (`Ate/Services`). Sharing is live on Supabase (`publish-recipe` edge function → `shared_recipes`); a server-side `parse-recipe` fallback is not deployed yet.
- Config lives in `project.yml` build settings and is read from Info.plist: `ATE_BACKEND_MODE` (`ondevice` | `mock` | `supabase`), `ATE_SUPABASE_URL`, `ATE_SUPABASE_PUBLISHABLE_KEY` (publishable/anon key only), `ATE_SHARE_HOST`, `ATE_SHARE_URL_TEMPLATE` (`…/r/?s={slug}`). **No secret keys in the app.**
- **Default runtime modes:**

  | Build | AI parsing | Sharing | Sync / accounts |
  |---|---|---|---|
  | CI / sideload `.ipa` (`ATE_BACKEND_MODE=ondevice`) | On-device Apple Intelligence (iOS 26 + supported hardware). JSON-LD for recipe pages; otherwise demo cards badged "Demo" | Supabase Edge Function `publish-recipe` → `shared_recipes` (links `<ATE_SHARE_HOST>/r/<slug>` and `ate://recipe/<slug>`) | Supabase Auth + `user_recipes` (RLS), when signed in |
  | `ATE_BACKEND_MODE=supabase` | Server `parse-recipe` (not deployed) | Supabase | Supabase |
  | `ATE_BACKEND_MODE=mock` and UI tests (`-UITesting`) | Mock | In-memory mock | Mock auth |

## Build locally (macOS)
```sh
brew install xcodegen
bash scripts/prepare-local-build.sh
open Ate.xcodeproj   # Xcode 26 (iOS 26 SDK) required for the Foundation Models code path
```

Before opening Xcode, run `bash scripts/prepare-local-build.sh` after checking out or switching branches. It generates the Xcode project with a local version based on the Git commit count (`0.1.<commit-count>`), the same value as the build number, and the current short Git SHA embedded for diagnostics. The script temporarily overrides `project.yml` and restores it afterwards, so CI's source-of-truth defaults remain unchanged. CI release IPAs continue to use the GitHub Actions run number and their existing artifact validation. If you run plain `xcodegen generate`, rerun the helper to restore the local version in Xcode. Do not commit local-only version changes in the generated `Ate.xcodeproj/project.pbxproj`.

## CI → .ipa
`.github/workflows/build-ipa.yml` runs on pushes to `main`, and can also be started manually. Every main push builds and archives the app, performs release-artifact and simulator launch smoke checks, and updates **`latest-build`**; this is an internal build, not a validated beta. Unit tests, the 8-flow `KeyFlowsQATests` gate, focused Cooking Tracker/Cook Mode regressions, the full UI-test shards and backend E2E run only when a manual run sets `run_tests=true` or the pushed commit message contains `[run tests]`. A successful full validation promotes that exact build to **`latest-beta`**. The shorter PR gate is defined in [`.github/workflows/compile-check.yml`](.github/workflows/compile-check.yml); deliberate release-candidate verification is [Pre-production QA](.github/workflows/preproduction-qa.yml) and its policy is in [docs/QA.md](docs/QA.md):

**Download on your phone:** https://github.com/melusi-k/ate-ios/releases/tag/latest-build

### Installing the .ipa (current: 0.1.0 build 99)
1. **SideStore (recommended):** in SideStore tap **+**, pick the downloaded `Ate-<version>-build<N>.ipa`, choose **Keep** app extensions. SideStore registers the App Group for free Apple IDs (widgets work) and refreshes on-device every 7 days.
2. **AltStore / Sideloadly:** same IPA; re-sign every 7 days. In Sideloadly leave *Remove app extensions* off.
3. **Xcode (Mac):** build with your Personal Team (see *Build locally*).

Verify the download first: each release has `<ipa>.sha256` and lists the SHA-256 in its notes (`shasum -a 256 -c Ate-…ipa.sha256`). CI downloads the published asset and re-checks it (A-CI-06) before the release stands.

- **Unsigned build** (the default, when no signing secrets are set): any of the sideload routes above re-signs the app for your device. A free Apple ID gives you a 7-day signature.
- **Signed build** (when the secrets below are set): install via Apple Configurator / Finder, or a tool like Diawi. Your device's UDID must be in the provisioning profile.

### Signing secrets
Add these under repo **Settings → Secrets and variables → Actions**:

| Secret | How to get it |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Export your Apple Development (or Distribution) certificate + key from Keychain as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password you set for the `.p12` |
| `BUILD_PROVISION_PROFILE_BASE64` | Development or Ad Hoc profile for your App ID (e.g. `com.melusik.ate`) with your devices: `base64 -i profile.mobileprovision \| pbcopy` |
| `WIDGET_PROVISION_PROFILE_BASE64` | Profile for `com.melusik.ate.widgets` (Live Activity / widget extension) |
| `SHARE_PROVISION_PROFILE_BASE64` | Profile for `com.melusik.ate.share` ("Save to ate" share extension) |
| `WATCH_PROVISION_PROFILE_BASE64` | Profile for `com.melusik.ate.watchkitapp` (Apple Watch app) |
| `WATCH_WIDGET_PROVISION_PROFILE_BASE64` | Profile for `com.melusik.ate.watchkitapp.widgets` (watch complication) |
| `TEAM_ID` | 10-character Apple Developer Team ID |

Every embedded bundle needs its own profile, and all of them need the App Group `group.com.melusik.ate`. CI regenerates the project with each profile assigned to its target (`ATE_PROFILE_*`), then exports with a bundle-ID → profile map. The export method (development / ad-hoc) comes from the app profile. A missing extension profile makes the signed export fail and name that bundle.

```sh
gh secret set BUILD_CERTIFICATE_BASE64 < <(base64 -i cert.p12)
gh secret set P12_PASSWORD
gh secret set BUILD_PROVISION_PROFILE_BASE64 < <(base64 -i app.mobileprovision)
gh secret set WIDGET_PROVISION_PROFILE_BASE64 < <(base64 -i widgets.mobileprovision)
gh secret set SHARE_PROVISION_PROFILE_BASE64 < <(base64 -i share.mobileprovision)
gh secret set WATCH_PROVISION_PROFILE_BASE64 < <(base64 -i watch.mobileprovision)
gh secret set WATCH_WIDGET_PROVISION_PROFILE_BASE64 < <(base64 -i watch-widgets.mobileprovision)
gh secret set TEAM_ID
```

## Fonts
Fraunces and DM Sans (SIL OFL, licenses in `Ate/Resources/Fonts`) are bundled. If a font fails to load, the app falls back to the system serif or sans font.

## v1.1 additions
- **Live Activity** for cook timers (`AteWidgets` extension, embedded in `PlugIns/`). **Sticky timer bar** on every screen.
- **Accounts & sync** with Supabase Auth (email/password + magic link). Recipes and shopping list sync last-write-wins and offline-first. Works signed-out.
- **Sharing:** "Share link" sends one link with a rich preview; "Share as text" sends clean text. Deep links: `ate://recipe/<slug>` (alias `ate://r/<slug>`). The share domain lives in one setting, `ATE_SHARE_HOST`.
- **Build number and version:** CI sets `MARKETING_VERSION=0.1.<run_number>`, `CURRENT_PROJECT_VERSION=<run_number>` and `ATE_GIT_SHA`, then checks them inside the built `.ipa` (the job fails on a mismatch). Each build is published as `Ate-<version>-build<N>.ipa`: it is the only asset on the rolling `latest-build` prerelease, and it also goes on a permanent `build-<N>` prerelease. Settings shows `ate <version> (build N) · <sha> · backend <ref>` (tap to copy).
- **Entitlements:** the App Group `group.com.melusik.ate` is used by both targets, with a fallback to standard storage if it isn't granted. Associated domains (`applinks:ate.app`, `applinks:recipe-transform-ai.lovable.app`) are added only for signed builds (`Ate/Ate-Signed.entitlements`). `DEVELOPMENT_TEAM` comes from the `TEAM_ID` env/secret.
- `PrivacyInfo.xcprivacy` for the app and the widget: no tracking; UserDefaults reasons CA92.1 and 1C8F.1; collects email, user ID and recipe content for app functionality.

### One-time Supabase setup (needed for sync)
1. Apply `supabase/migrations/20261010000000_user_recipes.sql`, `20261011130000_authenticated_sharing.sql`, and `20261011130500_security_function_search_path.sql` (already applied to the Ate production project; use the Supabase migration workflow for new environments).
2. Under Authentication → Providers, enable **Email**. Decide whether new accounts need to confirm their email.
3. Under Authentication → URL Configuration, add `ate://auth-callback` to the allowed **Redirect URLs** (for magic links and email confirmation).

### Sideloadly: keep the extensions (Live Activity / Dynamic Island)
The Live Activity is drawn by the **AteWidgets** extension (`PlugIns/AteWidgets.appex`, `com.melusik.ate.widgets`). If Sideloadly drops it, timers still run in the app but nothing appears on the Lock Screen or in the Dynamic Island.
- In Sideloadly › **Advanced options**, leave **"Remove extensions"** (a.k.a. *Remove app extensions / PlugIns*) **unticked** — i.e. keep extensions. Ticking it saves App IDs but deletes the widget, the share extension and the watch app.
- Leave **"Change bundle ID"** off unless you hit a conflict. If you change it, Sideloadly re-prefixes every extension (`<new id>.widgets`), which is fine; what breaks is an extension whose ID is no longer a child of the app's.
- Free Apple IDs get **10 App IDs per 7 days**. ate now has 5 bundles (app, widgets, share, watch, watch widgets). If Sideloadly fails with "maximum App ID limit", wait a few days or remove extensions you don't need — but the widgets one is required for Live Activities.
- After installing, check **Settings › About › Live Activity**: it shows `areActivitiesEnabled`, the last request result or error, the active count, the app/extension bundle IDs and the PlugIns present. "Widget extension: MISSING" means it was stripped; `areActivitiesEnabled: NO` means Settings › ate › **Live Activities** is off.

### Apple Watch app (watchOS 11+, independent)
`Ate.app/Watch/AteWatch.app` is embedded in the `.ipa` and also runs on its own (`WKRunsIndependentlyOfCompanionApp = YES`): sign in on the wrist with an email code, or open ate on a paired, signed-in iPhone and the session is handed over via WatchConnectivity.
**Free Apple ID limits:** Sideloadly and AltStore generally **do not install watch apps** (they install the iPhone app only and may strip `Watch/`). Installing the watch app needs Xcode (run the AteWatch scheme on your paired watch with your Apple ID — free IDs work but expire in 7 days and count 2 more App IDs) or a paid account (TestFlight / signed builds).

### Free Apple ID vs paid
| Works with a free Apple ID (Sideloadly) | Needs a paid Developer account |
|---|---|
| App, SwiftData, cook timers, local notifications, timer bar | Universal Links / Associated Domains (`ate.app`) |
| Live Activity + Dynamic Island (re-signed extension) | Signed CI builds / TestFlight / push-updated Live Activities |
| Supabase accounts & sync, deep links `ate://…` | Sign in with Apple, CloudKit |
| App Group (usually granted; falls back gracefully) | Apps that don't expire every 7 days |

Free IDs also allow only about 3 sideloaded apps and 10 App IDs per week. ate uses up to 5 App IDs (app, widgets, share, watch, watch widgets).

## License

Proprietary. Copyright (c) 2026 Melusi Khumalo. All rights reserved. The source is visible for transparency only; see [LICENSE](LICENSE).
