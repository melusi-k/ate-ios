# Food diary responsiveness candidate and test phases

Base: #535 hosted `5099f06e0a316d80add93c6d22d9c57454dd81db`.
Native execution for both changes remains UNRUN. No cause or fix is proven.

The failing test in run 43687433870, job 132730763152, reaches its 240-second
allowance at the source-name keyboard query. However, most lost time occurs
before source name: accessory lookup at 38.13s, failure snapshot 61.27s,
fallback Add tap 63.48s, foodName query 79.82s, Log-food navigation-bar reads
97.98/124.43/146.10/164.77s, first food-name tap 172.95s, quantity-unit typing
193.74s, source-name lookup 203.48s, one scroll 228.83s, field tap 236.96s,
keyboard query 239.99s. The test never reaches the source-choice sheet.

Earlier #535 retained runs complete this exact test: 106.782s in the 0721
archive (first food-name tap 33.37s, source-name 57.12s) and 86.700s in the
0558 archive (food-name 29.78s, source-name 50.05s). These native comparisons
do not prove identical ancestry or host conditions. In the failing current
run, 13 other UI tests pass, including the keyboard-resigned diagnostic.
That diagnostic's PASS does not isolate the current failure, because the
failing test has not yet reached its source-picker interaction.

The XCTest-owned deadline Spindump attachment
`2B2F7A6A-4126-41DC-B862-77DBFB338782.txt` contains a 4.98-second window.
Only Ate PID 41518 was inspected. Its Main thread handles AX snapshots,
SwiftUI updates, and repeatedly reaches a Mach run-loop wait. This does not
show continuous app deadlock. App source frames include the background
Settings LiveActivityDiagnosticsView, whose two-second timer invalidates
`.id(tick)` and re-reads ActivityAuthorizationInfo through synchronous XPC,
plus PlugIns-directory metadata. Only a few samples show these source
frames. This is a plausible source of needless redraw/query work, not proof
of the much earlier 79-165s query delays.

Commit 1 removes only that automatic two-second diagnostic refresh. All
fields, diagnostic getters, explicit Refresh button, and `.id(tick)` remain.
This applies to the diagnostic panel globally, not only when a diary sheet
is open. Live Activity operation and authorization policy are unchanged.
It is a responsiveness candidate, not a qualified fix.

Commit 2 inserts test-only `FOOD-FORM phase=... uptime=...` brackets around
existing launch, navigation, field, keyboard, source-picker and save work.
Only this required case prints them. The helper reads no UI/model values.
No new screenshots, AX queries, waits, retry rules, test inputs, selectors or
assertions are added. Stripping exactly the helper and calls reconstructs
the entire original XCTest source byte for byte. Existing hash contracts
remain unchanged after that explicit normalization. Commit 1 refreshes the
existing runtime-focus anchor to the hosted base without changing its pins.
MoreView was not an existing runtime pin. Commit 2 leaves runtime metadata
untouched so either commit can be dropped without a cross-commit fingerprint
dependency.

Next native evidence: original required case and original full gate, same
limits; inspect its timing brackets, retained pictures and XCTest stacks.
A quicker PASS supports usefulness, but does not on its own establish the
root cause. A repeated early query gap needs liveness/stack evidence from
that gap, not another source-name or timeout workaround.

Evidence URLs:
https://github.com/melusi-k/ate-ios/actions/runs/43687433870/job/132730763152
https://github.com/melusi-k/ate-ios/actions/runs/43687433870/artifacts/14153983229
