# Live query capture, PR 653

Diagnostic only. No product fix or green claim.

## Evidence

0ce8b386 normal Compile run44975487044 is RED. Tracker's returned-month predicate timed out and the following test could not terminate the app. Cook completion/history exceeded180 seconds. The Cook route, import/save and history assertions remain intact.

In account artifact14736679907, the Add sheet screenshot at03:16:28.689Z is rendered. App stdout shows the title query entering injected XCTest main-thread AX traversal at03:16:29.882Z, finding the correct title at03:17:02.158Z and replying02.195Z. Main-actor heartbeat callbacks run afterward. There is no sampled stack for that interval. This establishes app-hosted automation work, not a demonstrated business-logic cause. Older green run44050886868 also has long title-query retries.

https://github.com/melusi-k/ate-ios/actions/runs/44975487044/artifacts/14736679907
https://github.com/melusi-k/ate-ios/actions/runs/44050886868/artifacts/14327856702

## Changed capture

- Tracker returned-month predicate reads label once, retains it, and evaluates the original Foundation predicate against a dictionary containing that same label. The exact3-second waiter and completed assertion remain. Last returned label, expected label, result and monotonic time are emitted without a second post-failure AX read. Nil means no returned observation, not a mismatching label. Reviewer must check predicate equivalence.
- Fixed flushed markers surround that existing label read and the existing completion-journey Add-title wait. The latter is still conditional on the existing completion-only flag. No other journey gets markers.
- Two native commands acquire a host-only observer. One1-second app sample per named boundary is requested only while the boundary is open and10–30 seconds old. Fast/closed/stale boundaries do not trigger. At most two samples across both commands.
- Before sampling, retain ps process names and exact simulator launchctl services, both with stdout/stderr. Require one exact app service PID corroborated by the Ate.app/Ate executable. Missing, ambiguous, unverified or failed metadata stops capture without guessing. Each metadata command has a3-second diagnostic subprocess timeout; sample has a3-second diagnostic timeout. Stderr and partial files remain on failure.
- Recheck boundary and child state after metadata collection and record whether the boundary is still open after sampling. A boundary that closes during the sample is recorded honestly, not presented as a complete in-boundary capture.
- Existing wrapper forwards child signals, retains child exit status and joins its observer before returning. No simulator shutdown or detached sampler is introduced.

No source product, native selection, wait/cap, retry, route or acceptance change. Tracker previous-month and future-month restrictions remain. Cook still imports, saves, cooks, acknowledges completion, returns with pushed Back, and checks recorded history through the real Journal tab.

## Guards and validation

Exact pinned inverse composes before existing Today-tab and Cook-entry workflow guards. Historical fixture hashes are unchanged. New tests cover fresh/closed/stale boundaries, one capture per boundary, service/PID validation, metadata and sample error retention, timeout, real native nonzero exits, signal forwarding/join, inverse mutations and single-label-read source contract.

482 Python tests pass. actionlint passes with the existing custom runner-label configuration. Diff whitespace check passes. These are not Swift compilation, native acceptance or successful live-sample proof. First normal changed-head qualification is required. No retry, waiver or merge.
