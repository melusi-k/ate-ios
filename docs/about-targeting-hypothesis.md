# Settings About targeting hypothesis

Base e1ed821b9af18e253aafd2cb7cc9988731b510d7 plus the separate strict
history-independent Python guard correction. Native UNRUN.

The failed case spends 203 seconds in recipe/Library setup before Settings.
Quiet-hours and Step-alert setup then includes expensive queries, not simply
swipe count. About-version lookup starts at 389 seconds, already beyond the
existing six-minute allowance. It exists at 400 seconds but the generic
exists-and-hittable loop keeps swiping. There are no About-specific pixels
or AX trees proving the reason. This patch is targeting, not a proven fix.

Use the existing read-only-row geometry helper for the first aboutVersion
Text, like later About headings. It requires the full row inside the window
and clear of active Settings navigation, native tabs and bottom accessory.
The original version existence wait and build-label assertion remain.

Quiet-hours and Step-alert searches now swipe the already validated Settings
content collection instead of the whole application. Query identity,
existence waits, switch hittability assertions, short-circuit conditions,
25/50 directional bounds and directions are unchanged. Other scrollTo
callers keep the original application surface through the default argument.
No new retry, sleep, timeout or allowance change. No product changes.

The whole original test file is reconstructed exactly after reversing only
these targeting changes. The older launch-capture whole-file guard uses the
same reversal before its original hash, retaining both baselines.
Native compile, exposure, navigation, geometry and complete journey remain
UNRUN. QA7 runner initialization is separate and unchanged. No waiver.
Source PRs close only after Reviewer confirms destination commit; branches kept.
