# ate Privacy Policy

_Last updated: 23 October 2026 · [Earlier versions](policy-history.html)_

ate is a recipe app made by **Melusi Khumalo**, an individual developer based in South Africa ("I", "me"). I'm the responsible party (POPIA) and controller (GDPR) for the personal information described here. This policy explains what ate stores, where it's stored, and the choices you have. Questions: **melusi.l.k@gmail.com**.

## The short version
- ate works without an account. With no account, your recipes, shopping list and settings stay on your device.
- If you create an account, ate stores your email address plus your synced recipes and shopping list so they show up on your other devices.
- **Apple Health data is read on your iPhone only.** It's never uploaded, synced, shared or used for ads. See [Health data](health.html).
- Recipe AI and Image Playground covers run **on your device** using Apple Intelligence. See [AI disclosure](ai.html).
- No ads, cross-app tracking, or selling of data. Non-production builds send limited category-only telemetry to help improve reliability; production builds do not. See [Cookies and tracking](cookies.html).
- You can delete your account and its data at any time from inside the app. See [Delete your account](delete-account/).

## What ate stores

**On your device:** your recipe library, shopping list, timers, Insights journal entries, app settings and a small diagnostic event history. The diagnostic history records limited event categories (such as app launch, backgrounding, storage recovery and save failures) with timestamps. It does not record recipe content, prompts, account identifiers or raw error messages. It is capped at 200 events and can be exported or cleared in Settings › Diagnostic history. Recognized non-production builds also send allowlisted event categories and timestamps, plus app/build/channel metadata, to Supabase for up to 30 days. Production and unknown-channel builds do not send this telemetry. The remote payload excludes recipe content, prompts, account IDs and device IDs. Clearing local history does not delete events already received remotely. Your other local data stays on the device unless you sign in to sync recipes and your list.

**If you create an account:**
- **Account data:** your email address, a securely hashed password (if you use one) and basic sign-in records (when the account was created and last signed in).
- **Synced content:** your recipes and shopping-list items, so they stay in sync across your devices.
- **Beta test results (optional):** if you use a beta-channel build and tap upload on **Settings › Beta testing**, ate stores your check results and notes for that build, linked to your account, so I can fix bugs. This diagnostics area is hidden in production-channel builds. They're deleted with your account.

**If you share a recipe:** you must be signed in to create a share. ate publishes a read-only copy of that recipe (title, description, ingredients, steps and any image link) at a share link and records that it belongs to your account. **Anyone who has the link can view it.** Deleting your account removes the shares belonging to that account; older anonymous shares may remain available until you email me the link for removal (see [Delete your account](delete-account/)).

**Recipe links, screenshots and voice:** to read a recipe from a link, your device downloads that web page directly. Screenshots are read on your device with Apple's text recognition. Voice commands in cook mode use Apple's on-device speech recognition; if your device can't do it on-device, ate doesn't listen. None of these are uploaded to me.

## Apple Health and Journaling Suggestions
If you connect Apple Health, ate **reads** (never writes) your sleep, steps, active energy and workouts to show Insights and suggest recipes. This stays on your iPhone. If you allow Journaling Suggestions, a moment you pick stays in ate's own journal on your device. Full details: [Health data privacy](health.html).

## Widgets, Siri, Shortcuts and Spotlight
- **Widgets and Control Center:** ate writes a small snapshot (running timers, the next shopping items, tonight's pick, favourite covers) to a shared App Group container on your device so widgets can show it. It never leaves the device.
- **Siri, Shortcuts and App Intents:** your requests are handled by Apple. ate receives only the action and the recipe or item it names, and handles it on your device.
- **Spotlight:** recipe titles are indexed on your device so you can search for them. You can turn this off in iOS Settings › Siri › ate.

Apple's own handling of Siri and Spotlight is covered by [Apple's privacy policy](https://www.apple.com/legal/privacy/).

## Where data is stored
Account, synced data and shared recipes are stored with **Supabase** (a hosted database and authentication provider) in its **EU (Ireland, eu-west-1)** region. Data is encrypted in transit (HTTPS). Supabase acts as a processor on my behalf. Transfers from South Africa to the EU rely on the EU's adequate level of protection and Supabase's data processing terms. See [Subprocessors and data map](subprocessors.html).

> ⚖️ **Lawyer review needed:** confirm the POPIA section 72 transfer basis and whether a Supabase DPA has been signed.

## AI processing
ate uses **Apple Intelligence (Foundation Models) on your device** to turn links, screenshots and prompts into recipe cards, and **Image Playground** on your device to draw covers for recipes with no photo. ate doesn't send your recipe content to OpenAI, Google or any other AI provider, and there is no server-side AI. If on-device AI isn't available, ate shows a sample (demo) recipe card instead and tells you so. AI can be wrong: see [AI disclosure](ai.html).

## This website
- These pages and the shared-recipe page are hosted on **GitHub Pages**. GitHub may log your IP address and browser details to run and secure the service ([GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement)). I don't get those logs.
- When you open a share link, your browser fetches that recipe directly from Supabase EU. Supabase may log the request (including your IP address) for security.
- The site uses no cookies, analytics or trackers, and its fonts are served from the site itself.

## What ate doesn't do
- No advertising or third-party analytics SDK. Recognized non-production builds send a limited allowlist of diagnostic/product event categories and coarse build metadata to ate's existing Supabase project; production and unknown-channel builds do not. The event table contains no user, account or device identifier and is subject to 30-day retention. Supabase may process request metadata such as IP address for service security.
- No tracking across apps or websites, and no selling or renting of your data.
- No access to your contacts or location, and no photos beyond the single image you choose to import.

## Why I use your data (legal bases)
- **To provide the service you asked for** (sign-in, sync, sharing). This is contract performance.
- **Health data and Journaling Suggestions:** only with your explicit consent, given in Apple's permission sheet. You can withdraw it at any time in iOS Settings.
- **To keep ate secure and working**, including category-only non-production reliability telemetry and beta test results. This is a legitimate interest; telemetry is not used for advertising or profiling.
- I don't use your data for marketing.

> ⚖️ **Lawyer review needed:** confirm the legal bases, especially explicit consent for health data (POPIA s26–27, GDPR art. 9).

## How long data is kept
- **Account and synced data:** kept while your account exists. When you delete your account, your account, synced recipes, shopping list and beta results are deleted from the database straight away. Backups held by the hosting provider roll off within their normal backup cycle (typically up to 7 days).
- **Shared recipes:** stay available at their link while your account exists. Deleting your account removes owned shares; older anonymous shares stay available until you ask me to remove one. I'll remove requested links within 30 days, usually much sooner.
- **Data on your device**, including Health-derived Insights and journal entries: stays until you delete it, sign out and remove local data, or delete the app. Diagnostic history is limited to the most recent 200 events and can be cleared at any time in Settings.

## Your rights (POPIA and GDPR)
You can access, correct, delete and export your data, object to or restrict processing, withdraw consent, and complain to a regulator. How to do each of these: [Your data rights](rights.html). Email **melusi.l.k@gmail.com**; I'll reply within 30 days.

## Children
ate isn't directed at children under 13, and I don't knowingly collect personal information from them. If you believe a child has created an account, email me and I'll delete it.

## Security
Passwords are hashed by the authentication provider. Database rules make sure each account can only read its own synced data, and connections are encrypted. No system is perfectly secure. To report a problem, see [Security](security.html).

## Changes to this policy
If this policy changes, I'll update the date above and keep the old version in the [policy history](policy-history.html). If the changes are significant, I'll also tell you in the app before they take effect.

## Contact
Melusi Khumalo, South Africa · **melusi.l.k@gmail.com**
