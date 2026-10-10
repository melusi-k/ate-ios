# ate — iOS

Native SwiftUI (iOS 18+, iPhone; Apple Intelligence features need iOS 26 on supported hardware) rebuild of the **ate** AI recipe library. Full spec: [docs/PRD.md](docs/PRD.md).

**Beta gate:** [docs/MVP_CHECKLIST.md](docs/MVP_CHECKLIST.md) (score in [docs/MVP_SCORE.md](docs/MVP_SCORE.md)) · **QA gate:** [docs/QA.md](docs/QA.md) — `KeyFlowsQATests` must pass before CI publishes a release · Testers: [docs/BETA.md](docs/BETA.md).

## Features
Library + search · Add recipe sheet (Link / Image / Prompt → review/edit/regenerate/save) · Recipe detail (x1/x2/x3 scaling, inline edit, Ask ate rewrite, share, add to shopping list, delete) · Cook mode (big text, progress, step timers with background notifications, screen stays awake) · Shopping list (merge, manual add, tick, share/copy/.txt/.csv, clear) · Settings (private mode, units, timer prefs + quiet hours, export/import/clear) · Shared recipe deep links (`ate://recipe/<slug>`, legacy `ate://r/<slug>`) · 404 / error states.

Data is stored on-device with SwiftData. Settings live in UserDefaults.

## AI
- **Default: on-device.** Apple Foundation Models (`LanguageModelSession` + `@Generable` recipe type) on iOS 26+ devices with Apple Intelligence. Screenshots go through Vision OCR (`VNRecognizeTextRequest`). For links, the app fetches the page and passes its text to the model.
- If the system model isn't available (older iOS, unsupported device, Apple Intelligence off), links with schema.org page data still import via JSON-LD; everything else **falls back to demo cards** badged "Demo". The Add sheet and Settings show which one is active.
- Everything goes through the `BackendService` protocol (`Ate/Services`). Sharing is live on Supabase (`publish-recipe` edge function → `shared_recipes`); a server-side `parse-recipe` fallback is not deployed yet.
- Config lives in `project.yml` build settings and is read from Info.plist: `ATE_BACKEND_MODE` (`ondevice` | `mock` | `supabase`), `ATE_SUPABASE_URL`, `ATE_SUPABASE_PUBLISHABLE_KEY` (publishable/anon key only), `ATE_SHARE_HOST`. **No secret keys in the app.**
- **Default runtime modes:**

  | Build | AI parsing | Sharing | Sync / accounts |
  |---|---|---|---|
  | CI / sideload `.ipa` (`ATE_BACKEND_MODE=ondevice`) | On-device Apple Intelligence (iOS 26 + supported hardware). JSON-LD for recipe pages; otherwise demo cards badged "Demo" | Supabase Edge Function `publish-recipe` → `shared_recipes` (links `<ATE_SHARE_HOST>/r/<slug>` and `ate://recipe/<slug>`) | Supabase Auth + `user_recipes` (RLS), when signed in |
  | `ATE_BACKEND_MODE=supabase` | Server `parse-recipe` (not deployed) | Supabase | Supabase |
  | `ATE_BACKEND_MODE=mock` and UI tests (`-UITesting`) | Mock | In-memory mock | Mock auth |

## Build locally (macOS)
```sh
brew install xcodegen
xcodegen generate
open Ate.xcodeproj   # Xcode 26 (iOS 26 SDK) required for the Foundation Models code path
```

## CI → .ipa
`.github/workflows/build-ipa.yml` runs on every push to any branch, and you can also start it manually. It generates the project, runs the unit tests, archives the app, uploads `Ate-<version>-build<N>.ipa` as a workflow artifact, and replaces the **`latest-build`** prerelease:

**Download on your phone:** https://github.com/melusi-k/ate-ios/releases/tag/latest-build

### Installing the .ipa
- **Unsigned build** (the default, when no signing secrets are set): sideload with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) using your Apple ID. They re-sign the app for your device. A free Apple ID gives you a 7-day signature.
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
1. Run `supabase/migrations/20261010000000_user_recipes.sql` (SQL editor or `supabase db push`).
2. Under Authentication → Providers, enable **Email**. Decide whether new accounts need to confirm their email.
3. Under Authentication → URL Configuration, add `ate://auth-callback` to the allowed **Redirect URLs** (for magic links and email confirmation).

### Free Apple ID vs paid
| Works with a free Apple ID (Sideloadly) | Needs a paid Developer account |
|---|---|
| App, SwiftData, cook timers, local notifications, timer bar | Universal Links / Associated Domains (`ate.app`) |
| Live Activity + Dynamic Island (re-signed extension) | Signed CI builds / TestFlight / push-updated Live Activities |
| Supabase accounts & sync, deep links `ate://…` | Sign in with Apple, CloudKit |
| App Group (usually granted; falls back gracefully) | Apps that don't expire every 7 days |

Free IDs also allow only about 3 sideloaded apps and 10 App IDs per week. Ate uses 2 App IDs (app + widget).
