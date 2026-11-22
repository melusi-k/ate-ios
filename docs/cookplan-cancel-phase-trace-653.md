# CookPlan cancellation phase trace, PR653

Diagnostic only. No product fix, passing claim, timeout increase, retry, waiver or merge.

## Evidence and unresolved boundary

ccb187809f9a258cd240eb94fdb315446e959a4a is a real new CookPlan dismissal assertion RED. Cancel tap39.00s, synthesis43.07s, idle46.37s, absence wait46.47s, first existence47.63s, debug54.16s, second existence56.79s, failure triage62.88s. Reopen did not run. Earlier0ce8 same corrected journey passed52.948s.

Current hierarchy at04:23:40.466Z retains the cooking-plan sheet with Done and Save disabled and no cancellation error. Done is disabled only by busy in source. Late retained frames also show the sheet. The small video extract has only four encoded frames near its end, not a continuous seven-second record. App stdout contains XCTest traffic but no cancellation phase trace. These facts support an unfinished busy operation, not an identified notification or app-code cause.

https://github.com/melusi-k/ate-ios/actions/runs/44982883240/artifacts/14739676915
https://github.com/melusi-k/ate-ios/actions/runs/44975487044

## Fixed evidence in this slice

Only CookPlanUITests enables -qaCookPlanCancelDiagnostic. App phase output also requires DEBUG and UITesting. With the flag off, the helper returns without reading clocks, emitting output, scheduling work or touching state. No recipe ID, notification ID, user content, dates or error contents are emitted.

The existing code order and awaits remain. Stamps distinguish:

- Cancel handler entry, busy set, Task admission, local store cancellation, notification cancellation, success before dismiss, return from dismiss and catch.
- Sheet onDisappear, to separate calling dismiss from actual lifecycle disappearance.
- Prior no-reminder local save and ordered cleanup registration/await/result.
- Existing queue generation, queue Task admission, predecessor wait and work entry/result/exit.
- Removal continuation, utility dispatch admission, synchronous removal return, continuation return, pending-ID verification and pass/fail.

The test's fixed begin/end markers bracket the existing Cancel tap and strict10-second reminder-disappearance assertion. No query, retry or wait is added. The existing host watcher gains the named cancellation boundary and wraps the unchanged Nutrition native command. One1-second live app sample may be requested while that boundary is open and10–30 seconds old, using the same PID corroboration, metadata, stderr and failure receipts as the reviewed live-query observer. Test terminal output closes the boundary even if the assertion prevents the explicit end marker. Nutrition's original pipeline, child status and selection remain.

## Guards and next step

Exact inverse fixtures pin the source, test, watcher and workflow changes. Historical fixture hashes are unchanged. Intermediate workflow stages accepted by the new inverse are exact hashes from the already-pinned live-query and Cook-entry fixtures, not unscoped string exceptions. Existing historical guards still run against reconstructed sources.

487 Python tests pass, including unchanged await/Task/dispatch/action/assertion counts, phase order, flag scope, exact inverse mutants, named sampler freshness/closure and native pipeline selection/status checks. actionlint passes with existing custom runner labels. Whitespace check passes. This is not native Swift or live capture proof.

First normal changed-head native qualification must provide the phase chain and sampler receipt. Analyse the first missing return against prior cleanup and live sample, then propose only the source correction the evidence supports. A pass or no-trigger capture is non-reproduction, not retroactive proof of a fix. No further diagnostic round is planned. If the trace cannot settle the cause, report that limit rather than fabricate a fix.
