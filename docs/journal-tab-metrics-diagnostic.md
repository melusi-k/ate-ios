# Journal-tab capture only

Base #534 bc45b9588799da4eb1c603eb9e6dfe28e5918ed4. Native UNRUN.

Two screenshots in navigation-header-regressions.xcresult show Settings
collapsed after scroll, then the full native bar after tapping the selected
Settings tab. Journal is visibly present in the second capture. The strict
hittable waiter then fails. Pixels do not establish AX hit-testing.

This opt-in DEBUG/UITesting capture adds two text attachments: immediately
after the reveal screenshot and immediately before the original hittable
waiter. Each reads the same five named native tab buttons once: existence,
then (if present) frame, selected and hittable, with cumulative elapsed
seconds. The existing test adds -qaJournalTabMetrics to launch arguments;
the helper requires both this flag and -UITesting. No production code edits.

These AX reads may perturb timing and may themselves stall in a broken
snapshot system. Five entries per capture is a bounded read count, not a
wall-clock cap. Attachment completion is not guaranteed. Missing capture
output is not a false/empty metric. There is no polling, sleep, additional
tap, navigation fallback, timeout or retry change. Every original strict
assertion remains. A source contract reconstructs the original entire
CoverageUITests.swift by removing only the helper, its two call sites and
the diagnostic launch flag.

Compare successful and failed captures on the same runtime before assigning
cause. Older named-case passes and failures are heterogeneous; this packet
claims neither a product correction nor a waived red. In particular it does
not change Cook Finish, the later termination failure, #537 Add recipe query
traversal or the separate landscape grid query failure.

No publication, merge or source PR closure. Source PRs close only after the
reviewer confirms the destination commit; branches kept.

Native source:
https://github.com/melusi-k/ate-ios/actions/runs/43694805899/artifacts/14157323576
