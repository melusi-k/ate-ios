# Subprocessors and data map

_Last updated: 20 October 2026_

## Who processes data for ate

| Provider | What for | Data | Location |
|---|---|---|---|
| **Supabase** | Accounts, sync, shared recipes, beta results, non-production telemetry | Email, password hash, recipes, shopping list, shared recipe copies, request metadata, category-only event names/timestamps and app/build/channel metadata | EU, Ireland (AWS eu-west-1) |
| **GitHub (Pages)** | Hosting this website and the share page | Server logs (IP address, browser) | USA and global edge network |
| **GitHub (Releases)** | Hosting beta app downloads | Download logs | USA and global |
| **Apple** | Apple Intelligence, Image Playground, Siri, Spotlight, HealthKit, Journaling Suggestions | Processed on your device under Apple's own terms; ate sends Apple nothing | On your device |

There are no ads or external crash-reporting/analytics SDKs. Local diagnostic history is stored on the iPhone; recognized non-production builds also send allowlisted category-only events and coarse build metadata to Supabase. Production and unknown-channel builds do not send this telemetry; remote event rows are retained for up to 30 days.

> ⚖️ **Lawyer review needed:** confirm the GitHub transfer basis (EU–US Data Privacy Framework and POPIA s72), and whether Apple counts as a processor here.

## Data map

| Data | Stays on device | Sent to Supabase EU | Public |
|---|---|---|---|
| Recipes and shopping list | ✓ (no account) | ✓ if signed in | ✗ |
| Shared recipe copy | ✓ | ✓ | ✓ anyone with the link |
| Email and password hash | ✗ | ✓ | ✗ |
| Apple Health data and Insights | ✓ only | ✗ never | ✗ |
| Journal entries and moments | ✓ only | ✗ | ✗ |
| Widget snapshot (App Group) | ✓ only | ✗ | ✗ |
| Photos, screenshots, voice | ✓ only | ✗ | ✗ |
| AI prompts and results | ✓ only | ✗ (unless you save and sync the recipe) | ✗ |
| Beta test results | ✓ | ✓ only if you upload | ✗ |
| Non-production telemetry categories and build metadata | ✓ local history | ✓ by default on recognized non-production channels; up to 30 days | ✗ |

Changes to this list are recorded in the [policy history](policy-history.html). Questions: **melusi.l.k@gmail.com**.
