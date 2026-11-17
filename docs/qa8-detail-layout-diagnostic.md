# QA8 post-Exit detail-layout diagnostic

Base: #539 hosted `379d96fc855a8a54e58e2caa25fb5a96199963ad`.
Diagnostic only. No product fix, native pass, root cause or visual result claimed.

## Current evidence

Run 43695466124/job 132754949700's targeted process sample is valid for Ate
PID 56377, build 1783, but contains only seven Main-thread samples. All seven
are inside a UIKit/SwiftUI layout/update transaction. Two samples evaluate
RecipeDetailView.askCard: one in RecipeQuality.issues ->
Durations.minimumSeconds -> regex keyword handling, one constructing its
font. The other samples traverse safe-area, AttributeGraph, layout and toolbar
paths. These counts do not establish a 1/7 CPU percentage or a root cause.

QA8's Exit body returns at uptime 1680.00449. The utility diagnostic delivers
through 120 seconds while the MainActor diagnostic has no subsequent rows.
The UI test later fails its matching-snapshot query in 236.914 seconds.
This supports unavailable MainActor progress after Exit returned. It does
not show a synchronous Exit-body hang or prove RecipeQuality is slow.

Quality checks are synchronous in detail body, so repeated layout/body work
repeats them. The quality path is finite and pure on the inspected code:
it performs bounded-by-input recipe checks, keyword rules and regex matching.
For this small QA8 recipe there is no obvious unbounded algorithm, external
I/O or model mutation in that call. No quality caching or skipped checks are
introduced by this packet.

A separate hypothesis is geometry feedback. Detail's measured global host
bottom becomes State, then changes footer reserve/padding in a safeAreaInset.
The root chrome's measured top becomes State, then an environment value
used by the same reserve. Dismissing Cook Mode reintroduces mini-player and
timer chrome. The reserve formula depends on a host whose available size
can itself depend on the reserve. This is a candidate feedback path, not a
proven oscillation. No cycle warning was found in the supplied log window.

Group28 is separate: its Favourite tap starts 239.95s at the 240s allowance,
returns, and the original toast predicate succeeds at 243.05s. The test then
sorts, opens a context menu and exits at 261.48s. Xcode's later generic
"unexpected exit, crash, or test timeout" restart follows that known timeout;
without a crash report it does not establish an additional app crash.
This QA8 diagnostic does not fix or qualify Group28.

## What changes

Existing DEBUG + UITesting + `-qaQA8ExitFileDiagnostic` gates only. The new
numeric collector arms and resets at the existing first exit-enter marker.
No pre-Exit recipe-creation activity consumes the row budget.

- Wrap the exact original RecipeQuality.issues invocation once, returning
  its unchanged result. Record begin, elapsed milliseconds and maximum call
  milliseconds. The elapsed window excludes diagnostic-file writes.
- Record proposed and previous values in the existing detail host-bottom
  and root chrome-top preference callbacks. Detail also records the current
  reserve before the unchanged State assignment. No new geometry query,
  preference key, State, layout modifier or measurement is introduced.
- At most 64 short numeric rows per process. Each phase emits its first four
  occurrences, then powers of two. Count jumps are deliberate decimation,
  not retries or missing data. The final row may precede the last event.
- Retain `qa8-detail-layout-PID.txt` in the existing `qa8-target-sample` Dog
  artifact. All existing sample semantics, assertions, test sources, timers,
  quality rules, selectors and qualification budgets remain unchanged.

The collector has no observable state, worker, timer, extra AX query,
recipe contents, names or user-data reads. It does perform synchronous
bounded atomic numeric file writes on Main. It can perturb timing; a pass
under instrumentation is not proof of unperturbed performance. Disk errors
print a fixed diagnostic marker and do not change product state.

## How to interpret

An unmatched quality-begin with no end narrows the interval to one call,
but does not by itself prove an algorithmic hang. Many completed short calls
at increasing counts support repeated body evaluation rather than one long
quality computation. Repeated host/chrome values alternating with reserve
changes would support geometry feedback. Converged geometry while quality
and layout continue argues against that particular feedback path. Retain
the original sparse stack sample and liveness rows for time/PID correlation.
A 64-row cap or a missing file is not evidence of no churn.

## Verification and limits

Linux Python contracts reconstruct entire original app/workflow sources by
removing only exact diagnostic additions; existing hashes remain unchanged.
App logic and XCTest sources remain byte-identical. Swift grammar parsing
is not native type-checking. Native compile, actual callback delivery,
geometry values, pixels and diagnostic capture are UNRUN. The reviewer must
run the original gates unchanged. No merge, publication or PR closure is
included. Source PRs close only after the reviewer confirms the destination
commit; branches kept.

Evidence:
https://github.com/melusi-k/ate-ios/actions/runs/43695466124/artifacts/14155298497
