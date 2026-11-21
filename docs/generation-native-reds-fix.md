# Generation native reds correction

Baseline: bec3b158, Compile44681551693, full-unit artifact14608666750. This packet
is a direct descendant of PR632's verifiedc59674c6 source. No lanes, popup, schema
or catalog changes are mixed in.

## Test-order defect

RecipeStreamingTests line128 assumed its initial preview survives an await of
XCTest fulfillment while a20ms deadline is already running. Production may
correctly revoke and clear that preview before the assertion resumes. This new
test was introduced byf82e8e5f0; the log does not label which loop iteration failed,
so the deadline-iteration attribution remains source-supported, not phase-proven.

The exact NotNil requirement now runs synchronously immediately after publication,
before started fulfillment or suspension, with the scenario name in its message.
Deadline expiry is explicitly observed through the session's loading transition
and timeout message, not a fixed60ms sleep. The observer yields the main actor and
is cancelled after the existing2s XCTest bound. The20ms diagnostic deadline and
60s normal session bound are unchanged. All prior cancellation/account/stale-sink,
new-preview, exact New result, nil-preview and no-save checks remain unchanged.
No production streaming code is changed, and this timing test defect does not
explain device generation misbehavior.

## Caption grouping product defect

SourceDraftImportc1267c757 classified a whole one-line Instagram caption containing
Fry/Season as a method row, despite measured ingredients on the same row. Its
OnDeviceBackend route7f957b576 fell through to that selector when AI was unavailable
or classification failed. The exact inline-caption ingredient verifier already
worked; the native same-run five-ingredient contract test passed. The numbered
paste importer deliberately declined this non-numbered/multiline layout.
Assertionb3cf602514 exposed the empty ingredient field; it did not create the bug.

The narrow inlineCaptionCard conversion uses only the existing verified measured
inline-caption contract. It carries the exact known ingredients/order/amounts and
written method, keeps original raw input as sourceDraft text, source imported and
editable, and leaves unknown servings/time/step timers blank. Title uses only an
already-recognized source dish, otherwise Imported recipe. No pastedSource
certification, arbitrary prose/sentence splitting, inferred ingredient, repair,
second model pass or demo fallback. The contract validates the produced card.

The conversion occurs before any model allocation on Add's shared source-import
route. A configured failing classifier is never called for the verified caption.
Ambiguous captions do not acquire this deterministic verified ingredient list;
their original editable raw-source path remains. Source-backed explicit Rerun is
unchanged and still uses its existing single-pass classifier, not this new Add
shortcut.

The original nonempty-ingredient native assertion remains and now checks exact
five ingredient names/quantities/units, written method, raw source, imported draft,
unknown facts and zero backend calls. Two additional native methods cover the
available-but-must-not-run classifier path and ambiguous-caption non-invention.
All prior native test bodies outside these exact additions/order correction are
retained by pinned exact inverses; old hashes are unchanged. Required-name ledger
increases144→147, adding the original failing caption method and the two new cases.

This can fix an empty ingredient field for an already-verified one-line measured
caption on device when Add previously took the deterministic fallback. It is not
a demonstrated fix for model latency, generation hangs, menus or other output.

## Qualification boundary

Native failing baseline was inspected directly. No new native compile/test ran.
The correction must be natively executed on its exact final source by Reviewer;
local Python checks and source inverses are not Swift or on-device qualification.
If reason-labelled streaming evidence contradicts the deadline diagnosis, keep
it red and investigate. No timeout, allowance or native assertion was weakened.

Observed sources:
- https://github.com/melusi-k/ate-ios/actions/runs/44681551693/artifacts/14608666750
- https://github.com/melusi-k/ate-ios/pull/632
