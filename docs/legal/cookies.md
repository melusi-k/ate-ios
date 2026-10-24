# Cookies and tracking

_Last updated: 23 October 2026_

**Short version: no cookies, ads, or cross-app tracking.** The website has no analytics. Recognized non-production app builds send limited category-only telemetry to improve reliability; production and unknown-channel builds do not.

## This website
- No cookies are set, and there's no cookie banner because there's nothing to consent to.
- No analytics, ad pixels, social embeds or third-party scripts.
- Fonts (DM Sans and Fraunces, under the SIL Open Font License) are served from this site, not Google Fonts, so loading a page doesn't contact Google.
- The shared-recipe page reads the recipe from Supabase EU in your browser. It stores nothing in your browser.
- GitHub Pages, which hosts the site, keeps server logs for security. See the [Privacy Policy](privacy.html#this-website).

## The app
- No ad or third-party analytics SDKs, and no cross-app tracking. Recognized non-production channels send only allowlisted event categories and coarse app/build metadata to Supabase; production and unknown-channel builds do not. This is not advertising, cross-app tracking, or profiling, and ate never asks for App Tracking Transparency permission.
- ate's App Store privacy label and its `PrivacyInfo.xcprivacy` manifest declare no tracking.

The non-production telemetry policy is described in the [Privacy Policy](privacy.html) and [subprocessor list](subprocessors.html). If the policy changes materially, I'll update these pages and ask for consent where the law requires it.
