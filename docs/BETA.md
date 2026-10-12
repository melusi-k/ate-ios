# What to expect in the ate beta

Thanks for testing ate. This is a controlled beta: the core works, some edges are rough. Beta diagnostics are available only in explicitly named beta-channel builds: open **Settings › Beta testing**. The Beta banner and entry are hidden in production builds; if you cannot see them, confirm that the installed build was produced with a recognized beta channel (normally `TierA`).

- **Install (build 99):** ate is sideloaded with a free Apple ID. Use **SideStore** first (keeps widgets working and refreshes on the phone), then AltStore or Sideloadly. You'll need Developer Mode, and the app has to be re-signed **every 7 days**. Your recipes survive re-signing. Check the IPA against the `.sha256` file on the release page.
- **What to test:** the in-app list under Settings › Beta testing is the same list as docs/MVP_CHECKLIST.md (Tier A and Tier C IDs).
- **AI:** drafts are made on your iPhone with Apple Intelligence (iPhone 15 Pro or newer, iOS 26, Apple Intelligence on). No recipe content goes to a third-party AI. Without Apple Intelligence, links with recipe page data still import; other inputs give a simple demo draft. Check quantities, times and allergens before cooking.
- **Social links:** Instagram and TikTok often hide captions. If a link doesn't import, paste the caption into Prompt.
- **Sharing:** sign in before creating a web share link. A shared recipe is read-only and anyone with the link can view it. You get a web link plus an `ate://recipe/…` link. Links don't open the app automatically for other people yet (universal links need a paid developer account); send the `ate://` link to friends who have ate. If you are not signed in, use Share as text instead.
- **Accounts:** optional for local use, required for cloud sync and creating share links. Confirmation and reset emails are limited to a few per hour.
- **Widgets, Control Center and Siri:** add the ate widgets from the Home Screen (long-press → Edit → Add Widget → ate) and the Kitchen timer from Control Center. On a free Apple ID the widgets may only say "Open ate" if Sideloadly didn't keep the App Group; check Settings › Beta testing › Widgets. Siri ("Start cook mode in ate", "Add milk to my ate list") works regardless.
- **Your data:** export it from Settings › Your data now and then.
- **Feedback:** melusi.l.k@gmail.com — say what you tapped, what you expected, and include a screenshot plus the version line from Settings › About.

## Widgets on a free Apple ID (App Group)

Widgets need the app and the widget to share an App Group. Since build 71, ate finds whichever group the signer actually granted, so a renamed group (for example `group.com.melusik.ate.TEAMID`) works too. Check **Settings › Beta testing › Widgets**: it shows `App Group OK: <group> (<source>)` or `App Group missing`.

If it still says missing after a Sideloadly install, Sideloadly didn't register a group for your Apple ID. Try these in order:

1. **Sideloadly:** open *Advanced options*. Leave *Remove app extensions* **off**, leave the bundle ID as is, and keep *Signing mode* on *Apple ID sideload*. Install over the existing app with the same Apple ID so your recipes stay.
2. **SideStore or AltStore:** these register an App Group for free Apple IDs (named `group.com.melusik.ate.<TEAMID>`) for the app and the widget. ate picks it up automatically. When it asks whether to keep the app extensions, choose **Keep**. Each extension uses one of your 10 App IDs per 7 days.
3. **Xcode (Mac):** open the project, choose your *Personal Team* for ate and AteWidgets, and add App Groups → `group.com.melusik.ate` (or let Xcode suggest one) on both targets. Run on your phone. The free-account limits still apply: 10 App IDs per 7 days, 3 apps per device, re-sign every 7 days.

Siri, Spotlight and the Control Center controls that only open the app work without the App Group.
