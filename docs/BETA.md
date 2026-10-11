# What to expect in the ate beta

Thanks for testing ate. This is a controlled beta: the core works, some edges are rough.

- **Install:** ate is sideloaded (Sideloadly/AltStore) with a free Apple ID. You'll need Developer Mode, and the app has to be re-signed **every 7 days**. Your recipes survive re-signing.
- **AI:** drafts are made on your iPhone with Apple Intelligence (iPhone 15 Pro or newer, iOS 26, Apple Intelligence on). No recipe content goes to a third-party AI. Without Apple Intelligence, links with recipe page data still import; other inputs give a simple demo draft. Check quantities, times and allergens before cooking.
- **Social links:** Instagram and TikTok often hide captions. If a link doesn't import, paste the caption into Prompt.
- **Sharing:** you get a web link plus an `ate://recipe/…` link. Right now the **web page can't show recipes shared from the iOS app** (it's being moved to the new backend), and links don't open the app automatically for other people yet (universal links need a paid developer account). Send the `ate://` link to friends who have ate.
- **Accounts:** optional. Confirmation and reset emails are limited to a few per hour.
- **Widgets, Control Center and Siri:** add the ate widgets from the Home Screen (long-press → Edit → Add Widget → ate) and the Kitchen timer from Control Center. On a free Apple ID the widgets may only say "Open ate" if Sideloadly didn't keep the App Group; check Beta testing › Widgets. Siri ("Start cook mode in ate", "Add milk to my ate list") works regardless.
- **Your data:** export it from Settings › Your data now and then.
- **Feedback:** melusi.l.k@gmail.com — say what you tapped, what you expected, and include a screenshot plus the version line from Settings › About.

## Widgets on a free Apple ID (App Group)

Widgets need the app and the widget to share an App Group. Since build 71, ate finds whichever group the signer actually granted, so a renamed group (for example `group.com.melusik.ate.TEAMID`) works too. Check **Beta testing › Widgets**: it shows `App Group OK: <group> (<source>)` or `App Group missing`.

If it still says missing after a Sideloadly install, Sideloadly didn't register a group for your Apple ID. Try these in order:

1. **Sideloadly:** open *Advanced options*. Leave *Remove app extensions* **off**, leave the bundle ID as is, and keep *Signing mode* on *Apple ID sideload*. Install over the existing app with the same Apple ID so your recipes stay.
2. **SideStore or AltStore:** these register an App Group for free Apple IDs (named `group.com.melusik.ate.<TEAMID>`) for the app and the widget. ate picks it up automatically. When it asks whether to keep the app extensions, choose **Keep**. Each extension uses one of your 10 App IDs per 7 days.
3. **Xcode (Mac):** open the project, choose your *Personal Team* for ate and AteWidgets, and add App Groups → `group.com.melusik.ate` (or let Xcode suggest one) on both targets. Run on your phone. The free-account limits still apply: 10 App IDs per 7 days, 3 apps per device, re-sign every 7 days.

Siri, Spotlight and the Control Center controls that only open the app work without the App Group.
