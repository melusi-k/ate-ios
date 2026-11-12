# System cleanup wait: diagnosis and bounded callback candidate

## Evidence, not a blanket runner exemption

#497 head `4b3762430f0200284ee8b0aaa70cf4a7847b551b`:
[Compile run 43256182464, retained units](https://github.com/melusi-k/ate-ios/actions/runs/43256182464/artifacts/13974142150).
The supplied full log records:

- Line1889: `testCleanupRemovesEveryVerifiableSnapshot` starts at18:43:41.844 UTC.
- Line1890: at18:43:42.163, CoreSpotlight delete-all reports failed donation,
  CSIndexErrorDomain -1000 and SetStoreUpdateService connection invalidation4099.
- Line1891: the test exceeds its unchanged four-minute allowance. No XCTest
  assertion or Swift lock diagnostic appears in that interval.
- Line1910: test host restarts. Subsequent cases run, including the writer-fence
  test in0.341s. The final failing-test list still names this cleanup case.

A previous unrelated #493 head198c3036 attempt has the same sequence:
[run43236215091](https://github.com/melusi-k/ate-ios/actions/runs/43236215091).
Its recovered log starts the same test at14:33:24.150 UTC, reports the same
Spotlight connection invalidation at14:33:24.493 and reaches the same four-minute
allowance failure. Earlier #254/current-main unit attempts in the available
review record also timed out in this exact case, not new shopping assertions.
No prior passing execution of this case was recovered in this bounded search.

Live #497 SystemSurfaceCleanup.swift and Lane3WriterBoundaryTests.swift were
compared byte-for-byte with main527dfb6 and both match. Shopping did not change
these files. The existing test actually awaits production cleanup. Its order is
notifications, Live Activities, Spotlight, widget snapshots, activity log. The
Spotlight await has no application-level deadline. Reaching the Spotlight log
supports earlier phases having progressed; it is not evidence of a Swift flock
or MainActor deadlock. No stack sample/xcresult hang trace was supplied, so the
exact suspended frame and the OS callback's non-delivery are NOT conclusively
proven by console proximity alone. Do not call all runner failures equivalent.

Classification: repeatable OS-service wait exposure in app/test cleanup, likely
CoreSpotlight callback loss after XPC invalidation; not a proven shopping data
regression, not a harmless runner launch stall, and not a verified lock deadlock.

## Candidate

Use the callback form of deleteAllSearchableItems through a once-only terminal
result. A five-second application operation deadline returns false/unverified;
cancellation also returns false. A timer independent of the Swift task does not
wait for a noncooperative structured child. Late/duplicate callbacks cannot resume
the continuation twice or turn a previously unverified outcome into success.
The OS deletion is not cancellable here; a late underlying deletion can still
finish. Reset must retain control/quiescence until it verifies cleanup separately.

The existing cleanup already propagates false as the named `spotlight` surface;
ClearAllResetCoordinator retains its control record and blocks completion for
any uncleaned surface. This candidate preserves that contract. No empty success
substitute, test skip, assertion removal, test-timeout change or rerun is included.
The original Lane3 test and all workflows remain byte-identical. It may proceed
to its original snapshot assertions when Spotlight is unverified, exactly as its
original comment permits; this is not a claim that Spotlight erasure passed.

The deadline specifically bounds the asynchronous callback wait. It does not
promise recovery if the process/main thread is globally frozen, or if callback
registration itself synchronously blocks. Notification and ActivityKit waits are
unchanged and not claimed bounded by this fix. A fresh exact-head native run and
its xcresult/hang trace remain required if this case still stalls.

## Qualification and integration

Eight added native tests cover immediate success/error, never-returning callback,
duplicate/late completion, cancellation including pre-cancellation, invalid
intervals and actual cleanup reporting Spotlight failure while preserving strict
snapshot assertions. All native tests and actual Xcode behavior are NOT RUN
locally. Python185PASS and diffcheck are source checks only.

Branch base main527dfb6. Reviewer transports after checking current base and keeps
existing feature tests. No push, merge or new PR performed. This patch changes
SystemSurfaceCleanup's Spotlight method; when combining with the OFF-only passive
reset candidate, retain its static platform method shape and apply the same bounded
callback adapter there. Do not reintroduce the unbounded async method in that merge.
No production Journal activation or account reset is authorized by this patch.
