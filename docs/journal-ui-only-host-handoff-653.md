# Journal unit-host to UI-host handoff correction

Base: c204a6f9, PR #653. The existing normal Journal run 44990719292 retained a first-launch failure, not a migration-data assertion.

## Observed cause

The retained unit session launches AteTests host PID 16149 at 05:52:21Z and passes both JournalReflectionEdit cases. Unified host logs show that process exiting voluntarily with status 0 at 05:52:40.5Z. The UI runner PID 16312 starts next. The first CanonicalUpgrade case starts 05:52:50.9Z; its launch creates a new app PID 16431 at 05:52:54.5Z. At 05:52:55.2Z, however, the UI runner requests a background assertion for the dead old unit-host PID 16149. It is denied and the test fails at app.launch, before the first migration assertion.

This identifies the stale host handoff in the mixed unit/UI invocation. It does not explain the internal XCTest bookkeeping implementation, nor promise that every future simulator launch is immune to a different failure.

## Narrow correction

Journal's existing test-without-building command now selects only its two UI classes. The duplicate JournalReflectionEdit unit selector and its two console-pass requirements are removed from that invocation. The existing real reflection-edit UI pass requirement stays unchanged. Both unit methods remain in AteTests and are explicitly added to the existing blocking full-unit required-pass manifest, whose native xcresult validator rejects missing, skipped, failed and unknown results.

No new Mac job or second native invocation is added. No test body, launch helper, migration assertion, UI selector, existing skip, timeout, cap, gate, checkout, artifact path or status handling changes. The full-unit suite remains all AteTests. Its expected case count stays 1348; Journal's native count changes 29 to 27 because the 2 already-covered unit cases no longer execute a second time there. The first normal run must confirm those counts and named passes.

## Source guards and qualification

The pinned inverse restores the exact c204 workflow, manifest and historical named-pass guard. Protected hashes keep the three Journal native files, Compile workflow and native-result verifier byte-identical. Guards reject the old mixed selection and any missing relocated requirement. Behavioral fixtures use the real native-result verifier to reject each moved case when missing, skipped, failed or unknown.

Local checks are source and Python checks, not native qualification. Publish only as an ordinary descendant and inspect the next normal Compile/Journal results. Do not rerun c204, increase budgets, waive its red or merge on this source result. The separate CookPlan cancellation assertion and other UI reds remain named; this patch does not claim to fix them.

Evidence: Journal run 44990719292, artifact 14742765468; retained unit/UI session excerpts and unified host PID 16149/16431 excerpts reviewed with this packet.
