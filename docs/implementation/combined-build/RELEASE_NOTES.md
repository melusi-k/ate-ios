# Combined reviewed build candidate

NOT API-compatible for cloud upload; local use works; do not rely on cloud sync.
Local use here means the retained local-only path, not a new native execution pass.

## Main feature

Journal and Cook changes now share one candidate: a native, token-checked Journal delete confirmation; retained edit/error/retry behavior; shared Cook steps and reflection-only Finish; countdown observation in small leaf views; combined static ingredient and step accessibility rows; and visible root tabs while Settings scrolls.

The candidate also retains reviewed generation, photo/input lifetime, screenshot import, scoped rewrite and quality changes carried by the source branches. The Food Journal account graph, writer/reset and generation-contract work is included for qualification, not activation.

Food Journal activation stays OFF. Cooking is not an eaten-food log. The Settings community row is not in this build.

## What to Test

- Journal: one Cancel and one Delete action; Cancel retains entry; successful delete removes only the intended identity; failed delete/edit retains detail and raw input for explicit retry. History reloads after a committed change.
- Cook: shared step progress, timer countdown and expiry, Exit/Resume, ingredient quantities, sheet expansion/dismissal and bottom-bar spacing. Finish must remain reflection-only, with no meal or false Health entry.
- Accessibility: recipe rows retain quantity/name and step number/instruction. Journal action identifiers must each resolve to exactly one action.
- Settings: scroll its Form, then tap one hittable Journal root tab without a reveal gesture. Existing header journeys remain required.
- Generation/import: cancel, dismiss, replace input or retry delayed work; stale results must not overwrite the current draft or save against a retired owner. Check multi-dish photos, screenshot structure, photo questions and scoped rewrite behavior.
- Food Journal qualification: native graph/admission, canonical fixtures, retained leases, reset fences and archive consumers. Do not turn activation on based on this candidate.

## How to Test

1. Reviewer publishes the runtime union, confirms its hosted destination commit, then applies the full focus-only pin against that ancestor. Keep the source branches.
2. Build IPA uses the artifact-only route: run_tests=false, Production channel. This is a test build, not qualified, validation lanes skipped; exact-head native gates still running. The artifact is not evidence that standard unit/UI gates passed. Retain the independently running exact-head gates, both separately required AX/Settings invocations and their exact logs.
3. Install the resulting candidate on the intended normal-text iPhone18Pro. Exercise the journeys above and capture post-action screenshots, not only launch images. Native, VoiceOver and physical-device acceptance must refer to the final built source.
4. Compare tracker-root and Cook Exit/bottom-bars behavior with earlier run evidence before proposing any fix. Those investigations are queued, not fixed by this union.

## Evidence and unrun work

Local source checks:207 Python tests pass; build-focus ancestry/blob guard and build-note generation are checked separately in the packet report. These are not native qualification.

Unrun here: Xcode compilation, native XCTest/XCUITest, IPA production/install, VoiceOver, pixels, device timing/performance, widgets, Files picker, backend SQL/HTTP/auth and full end-to-end graph qualification. No production migration or activation was performed. Existing tracker-root and Cook Exit idle failures remain unresolved.

Packet2 pins twelve combined runtime evidence paths to hosted67ec3bc25fcfaf9865c7865cba5e83b7d528349d, tree76aa007b9b393ffcfeaa48e86e74e369f6f7df74. This ancestry/blob check is source binding, not native qualification.

## Cloud sync limitation and isolated403 correction

Ordinary production launch still constructs SupabaseSync: GET from user_recipes,
then direct POST upsert to user_recipes for recipe and shopping records. It does
not inject GenerationFencedSyncService; that service is bound only by the admitted
FoodJournalAppGraph. Production direct writes are reported denied, so this union
is NOT an API-compatible ordinary cloud-sync build and must not be shipped as one.
The safe standalone snapshot/receipt/writer admission route is unresolved.

The isolated403 commit now reports permission denial, not session expiry;401
keeps the existing unauthorized/session-expiry path. A focused native classifier
test is added but UNRUN. This message correction does not repair the sync route.
