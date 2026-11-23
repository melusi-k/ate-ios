# CookPlan removal-entry: deterministic gate replaces wall-clock entry bound

Base: `ef58846bf8e2ab54b3abfc09e39264187d7cd1cc` (main after #653).

## Failure history (cross-run, same signature)

- PR592 source `d81646f7e7334a8b7705ae1bd60432ce7413f535`, Compile run 44917186447, build-nutrition job 136885308475: `testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly` failed its 2s utility-entry expectation, 65.323s total (see cookplan-removal-entry-diagnostic.md).
- Head `47380107cd4b51373af5d398624878b39540a7a6`, Compile run 44968168282: same test, same unfulfilled "utility removal entered" expectation, 64.488s.
- Head `e57dda1b9ea0a8e8c1934f6fc55a00378b583549` (tree `4532526c628e79e198bd12ff4503dac8c8d34e72`, byte-identical to current main tree), Compile run 45009157802: sole unit red, same expectation, 36.393884s.

Three observed failures across three heads share the entry-expectation failure. Available monotonic diagnostics show delayed utility callback entry and later completion. The cause of the scheduling delay is not proven. No product defect was observed in those recorded semantic assertions. This change removes the fixed scheduler-latency assumption; it does not claim to improve product latency.

## Change (test-side only; no product code touched)

`AteTests/CookPlanNotificationTests.swift`:

- The `expectation(description: "utility removal entered")` + `await fulfillment(of: [started], timeout: 2)` pair is replaced by `CookRemovalEntryGate`, an NSLock-guarded single-waiter continuation gate. The utility callback calls `entered.signalEntry()` at exactly the point it previously fulfilled the expectation; the test suspends at `await entered.waitForEntry()` and resumes when the callback itself signals, with no wall-clock bound on scheduler latency.
- Every semantic assertion is retained verbatim: off-Main execution (`XCTAssertFalse(Thread.isMainThread, ...)`), identity preservation (`XCTAssertEqual(ids, ["cook-r1"], ...)`), no early completion (`XCTAssertFalse(returned, ...)` while the boundary is blocked, before `release.signal()`), and final completion (`XCTAssertTrue(returned)`). The `release` semaphore blocking protocol is unchanged. All 11 `cookRemovalDiagnostic` phases keep their exact names and positions, so the `cook_entry_sample.py` EntryWatch sampler and log correlation are unaffected.
- No retry, no longer configured timeout, no mock, no product-code change. A callback that never enters now stalls at the entry gate until the existing lane cap instead of producing a bounded expectation failure. The semantic assertions are retained, but failure reporting and detection latency differ. Native qualification is still required.

## Pin updates and exact inverse

- Forward pins updated to the new file hash `6fcbbda4253e61f94d0a0ffcd3d44070e31ec9e741e03b39051e3e2bab537489` in `scripts/tests/test_cook_entry_sample.py` (TEST_SHA) and `scripts/tests/passive_receipt_653_source_pins.json`; the diagnostic-stripped pin in `scripts/tests/test_cook_removal_phase_diagnostic.py` moves to `73ebbb792a5a6c773c9fc5f1483457f5396edfcacca97625bebbbce4c3c2f22a`.
- Historical hashes are preserved through `scripts/tests/cookplan_removal_entry_gate_delta.py` + `cookplan_removal_entry_gate_inverse.json` (fixture SHA `0835636e393f6c9282e24604424b68584c1bf27c694e981e34e521f8655a55fe`): `restore` maps the new file byte-for-byte back to parent `f74ce8876ea4962b52ee7b1da0649868c2c3b5bf184e2b30c5b6963ea438f934`, whose diagnostic-stripped hash remains `e8e42897e24abdbaf061c1b117df751de5443522663d51b8c0ea2027acc7596f`.
- New `scripts/tests/test_cookplan_removal_entry_gate.py` pins the forward contract (no wall-clock entry bound, no retry, every assertion and phase retained, single-resume gate) and the exact inverse.
- `test_cook_removal_off_main.py` pre-marker pin `fce7986310514337704a2f650904a3b84fc4651cba1b7a334c0a5885397c753b` is untouched: no byte before the `// Exercise the real off-Main boundary` marker changed.

## Validation

- Python suite: 511 tests PASS (507 existing + 4 new gate pins), 11.300s.
- `scripts/check-ids.py`: 181 IDs, ownership consistent.
- Product code, workflows, project.yml and scripts/full-unit-required.txt unchanged.
- Native compile/test qualification runs on the PR head in CI (exact-head Compile).
