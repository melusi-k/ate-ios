# Universal Links for ate.app (placeholder — needs a paid Apple Developer account)

Free Apple IDs (Sideloadly) can't use the Associated Domains capability, so this isn't wired into the build yet.

When the paid account and the `ate.app` domain are ready:
1. In `project.yml`, set `ATE_SHARE_HOST: "https://ate.app"`. All share links come from this one setting.
2. Copy `Ate.entitlements.example` to `Ate/Ate.entitlements` and add `CODE_SIGN_ENTITLEMENTS: Ate/Ate.entitlements` to the Ate target.
3. Host `apple-app-site-association` (no file extension, `Content-Type: application/json`) at `https://ate.app/.well-known/apple-app-site-association`. Replace `TEAMID` with your team ID.
4. Have the web app serve `/r/<slug>` too, so people without the app still see the recipe.

The app already routes `https://<any host>/r/<slug>` (via `onContinueUserActivity`), `ate://recipe/<slug>` and `ate://r/<slug>`.
