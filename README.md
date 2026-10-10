# ate — iOS

Native SwiftUI (iOS 17+, iPhone) rebuild of the **ate** AI recipe library. Full spec: [docs/PRD.md](docs/PRD.md).

## Features
Library + search · Add recipe sheet (Link / Image / Prompt → review/edit/regenerate/save) · Recipe detail (x1/x2/x3 scaling, inline edit, Ask ate rewrite, share, add to shopping list, delete) · Cook mode (big text, progress, step timers with background notifications, screen stays awake) · Shopping list (merge, manual add, tick, share/copy/.txt/.csv, clear) · Settings (private mode, units, timer prefs + quiet hours, export/import/clear) · Shared recipe deep links (`ate://r/<slug>`) · 404 / error states.

Data is stored on-device with SwiftData. Settings live in UserDefaults.

## AI
- **Default: on-device.** Apple Foundation Models (`LanguageModelSession` + `@Generable` recipe type) on iOS 26+ devices with Apple Intelligence. Screenshots go through Vision OCR (`VNRecognizeTextRequest`). For links, the app fetches the page and passes its text to the model.
- If the system model isn't available (older iOS, unsupported device, Apple Intelligence off), the app **falls back to a mock backend** that returns demo cards. The Add sheet and Settings show which one is active.
- Everything goes through the `BackendService` protocol (`Ate/Services`). `SupabaseBackend` is a stub for the Edge Functions `parse-recipe` / `publish-recipe` and the `shared_recipes` table.
- Config lives in `project.yml` build settings and is read from Info.plist: `ATE_BACKEND_MODE` (`ondevice` | `mock` | `supabase`), `ATE_SUPABASE_URL`, `ATE_SUPABASE_PUBLISHABLE_KEY` (publishable/anon key only), `ATE_SHARE_HOST`. **No secret keys in the app.**
- Sharing currently uses the mock publisher, so share links only resolve inside the same app session until the server is wired up.

## Build locally (macOS)
```sh
brew install xcodegen
xcodegen generate
open Ate.xcodeproj   # Xcode 26 (iOS 26 SDK) required for the Foundation Models code path
```

## CI → .ipa
`.github/workflows/build-ipa.yml` runs on every push to any branch, and you can also start it manually. It generates the project, runs the unit tests, archives the app, uploads `Ate.ipa` as a workflow artifact, and replaces the **`latest-build`** prerelease:

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
| `TEAM_ID` | 10-character Apple Developer Team ID |

The bundle ID and export method (development / ad-hoc) are read from the profile automatically.

```sh
gh secret set BUILD_CERTIFICATE_BASE64 < <(base64 -i cert.p12)
gh secret set P12_PASSWORD
gh secret set BUILD_PROVISION_PROFILE_BASE64 < <(base64 -i profile.mobileprovision)
gh secret set TEAM_ID
```

## Fonts
Fraunces and DM Sans (SIL OFL, licenses in `Ate/Resources/Fonts`) are bundled. If a font fails to load, the app falls back to the system serif or sans font.
