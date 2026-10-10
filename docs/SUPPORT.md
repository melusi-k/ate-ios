# ate beta — support FAQ (top 5 issues)

Contact: melusi.l.k@gmail.com. Please include your iPhone model, iOS version and build number (Settings › About).

**1. "ate stopped opening after a week."**
Sideloaded builds signed with a free Apple ID expire after **7 days**. Re-install the latest `.ipa` (or refresh it in AltStore/Sideloadly). Your recipes stay on the phone as long as you don't delete the app. Signed-in users can also pull them back from sync.

**2. "Untrusted Developer" when opening ate.**
Go to Settings › General › VPN & Device Management, tap the developer profile (your Apple ID email), then tap **Trust**.

**3. "Developer Mode required."**
Go to Settings › Privacy & Security › **Developer Mode**, switch it on, restart when asked, then confirm **Turn On**. (The option only appears after a sideloaded app has been installed once.)

**4. "The share link doesn't load on the web."**
Known issue: the web share page still reads the old backend, so links made in this beta won't load in a browser yet. The recipe is fine. A friend with ate can open the `ate://recipe/…` link, or you can use **Share as text**. Links also can't open the app automatically (universal links) until ate has a paid Apple developer account.

**5. "My confirmation / magic-link / reset email never arrived."**
Check Spam/Promotions. The beta uses Supabase's built-in mailer, which sends only a few emails per hour, so wait 10 minutes before trying again. Open the link **on the iPhone that has ate installed**. If it says the link expired, request a new one. You can keep using ate without an account in the meantime.

Other known limitations: see [BETA.md](BETA.md). AI recipes need iOS 26 and an iPhone 15 Pro or later with Apple Intelligence on. Otherwise you'll see "Demo" or "page data" badges.
