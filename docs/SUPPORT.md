# ate beta — support FAQ (top 5 issues)

Contact: melusi.l.k@gmail.com. Please include your iPhone model, iOS version and build number (Settings › About).

**1. "ate stopped opening after a week."**
Sideloaded builds signed with a free Apple ID expire after **7 days**. Re-install the latest `.ipa` (or refresh it in AltStore/Sideloadly). Your recipes stay on the phone as long as you don't delete the app. Signed-in users can also pull them back from sync.

**2. "Untrusted Developer" when opening ate.**
Go to Settings › General › VPN & Device Management, tap the developer profile (your Apple ID email), then tap **Trust**.

**3. "Developer Mode required."**
Go to Settings › Privacy & Security › **Developer Mode**, switch it on, restart when asked, then confirm **Turn On**. (The option only appears after a sideloaded app has been installed once.)

**4. "The share link doesn't load on the web."**
Resolved for new links (Tier A builds): shares now look like `https://melusi-k.github.io/ate-legal/r/?s=<code>` and open in any browser. Links made before this build (`recipe-transform-ai.lovable.app/r/…`) still open inside ate but not on the web — share the recipe again for a new link. Links can't open the app automatically (universal links) until ate has a paid Apple developer account; use the page's "Open in ate" button.

**5. "My confirmation / magic-link / reset email never arrived" or "Email limit reached".**
Check Spam/Promotions. The beta uses Supabase's built-in mailer, which sends only a few emails per hour, so wait 10 minutes before trying again. Open the link **on the iPhone that has ate installed**. If it says the link expired, request a new one. You can keep using ate without an account in the meantime.

**6. "Timers run but nothing shows in the Dynamic Island / Lock Screen."**
Open Settings › About › Live Activity. If it says *Widget extension: MISSING*, re-install with Sideloadly's **Remove extensions** option unticked (keep extensions). If *areActivitiesEnabled: NO*, turn on Settings › ate › Live Activities. If the last request shows an error, send us a screenshot of that panel.

**7. "The Apple Watch app didn't install."**
Sideloadly/AltStore with a free Apple ID usually install only the iPhone app. The watch app needs Xcode (free ID, 7-day expiry) or a paid developer account / TestFlight.

Beta diagnostics (Widgets, Health, Siri and checklist status) are available under **Settings › Beta testing** only in recognized beta-channel builds. Production builds intentionally hide this area and its banner. Other known limitations: see [BETA.md](BETA.md). AI recipes need iOS 26 and an iPhone 15 Pro or later with Apple Intelligence on. Otherwise you'll see "Demo" or "page data" badges.
