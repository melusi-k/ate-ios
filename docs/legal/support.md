# Support and FAQ

_Last updated: 11 October 2026_

Can't find an answer? Email **melusi.l.k@gmail.com** with your build number (Settings › Beta testing shows it).

## Installing
**How do I install the beta?** Download the latest `.ipa` from the [releases page](https://github.com/melusi-k/ate-ios/releases) and install it with one of these:
- **Sideloadly:** simplest. Leave **Remove app extensions** off and don't change the bundle ID. Widgets probably won't work (see below).
- **SideStore or AltStore:** better for widgets on a free Apple ID, and they can refresh the app automatically.
- **Xcode** on a Mac: build from source. Most reliable.

**The app stopped opening after 7 days.** Free Apple IDs sign apps for 7 days. Reinstall or refresh with SideStore or AltStore.

## Widgets
**Widgets don't show up, or show "Open ate".** Widgets need the widget extension and a shared App Group, and Sideloadly may drop or rename them. Open **Settings › Beta testing › Widgets** to see what's missing. If it says "missing", reinstall with SideStore, AltStore or Xcode. Siri and the Control Center controls work either way.

## Apple Health
**Connect Apple Health does nothing.** Update to the latest build, tap again, and check **iOS Settings › Health › Data Access & Devices › ate**. The Health line under Settings › Beta testing shows the status. Health data never leaves your phone: [Health data](health.html).

## Sync and account
**Do I need an account?** No. An account only adds sync between devices.
**My recipes aren't syncing.** Check you're signed in on both devices (Settings › Account & sync) and online. Tap **Sync now**.
**Delete my account:** [here's how](delete-account/).

## Siri and Shortcuts
**Siri gives a web answer instead.** Say "ate" in the phrase, like "Cook Mogodu in ate" or "What's tonight's pick in ate". Open ate once after installing so Siri learns the phrases.
**Siri picked the wrong recipe.** Update to build 74 or later. It now asks when it isn't sure.

## AI
**I got a "sample card".** On-device AI needs iOS 26 and Apple Intelligence. See [AI disclosure](ai.html).

## Other pages
[Release notes](releases.html) · [Security](security.html) · [Privacy](privacy.html)
