# Slice8: dormant refresh and snapshot re-admission coordinator

Local parent9c7c6b22e56fcb2c18ea246b50048fbea38f2ada (strict resources),
rootb670cf1. Re-pin to actual reviewed hosted parent before publication.
No ordinary launch/default sync/UI switch or Food Journal activation.

RecipeShoppingSessionRemount retires old owner capability and rotates its concrete
persistent epoch before refresh/new owner construction. Near-expiry session refresh
runs once, requires same nonempty account identity, uses a throwing full-session
persistence seam and verifies current full session afterward. No implicit account
switch. It constructs a new owner, snapshot-admits, consumes capture with an empty
push (no uploads), then builds graph (which must use strict resources/replay).

Run token, full-session and Task cancellation checks after every await prevent late
refresh/admission from remounting a retired graph. Explicit terminal retire also
invalidates a suspended candidate's real gate. True unauthorized refresh clears only
session via verified seam and reports signedOut, retaining local rows/metadata and
receipt. Other errors remain failed, no API success/reset/erase. Production factory
must bind the same actual session source/persistence used by every owner; not wired.

Three native tests UNRUN: old epoch refused before refresh, full refreshed bearer
snapshot before graph build; unauthorized refresh preserves personal fixture bytes
and receipt with zero build; deterministic suspended refresh retirement cannot
persist/build late result. No sleeps/timeouts.207 Python PASS; diff-check PASS.

Remaining auth integration: AppStore near-expiry branch still refuses pending final
factory remount. Snapshot401 with a not-near-expiry token needs explicit refresh
routing in that factory. Transport403/PT409 classification is in separately hosted
slice3a, not silently merged into this stack. Permission/API failures must never be
converted to expiry. No sign-in/account-switch adoption or signed-out local writer
mode invented. Shared writers/reset inventory and production mounting still pending.
Reviewer publishes only; source closures require destination confirmation; branches
kept.
