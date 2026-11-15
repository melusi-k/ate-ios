# Search input receipt: numeric diagnostic only

Exact base5a984fe2a1a299934762a5d0a6f4350d27870c82. Native UNRUN.
Current Explore case types miso once after focus=1/keyboard=1, but its full
value waiter fails and later pixels show mi. Older86ad583f similarly reports
mis after one miso input. d655b04d and214 runs pass the named case;0517 fails
before typing at focus readiness and is a different failure. No cause is
proven: input delivery, binding receipt, rendering/AX lag remain candidates.

DEBUG plus existing UITesting/qaSearchFocusDiagnostic opt-in wraps ONLY the
Search-tab binding. Original storage write happens once, unmodified. Capture
at most8setter events/24rows per process: phase1previous/incoming character
counts, phase2immediate stored count, phase3utility turnaround (first is
scheduled uptime, second utility uptime, row uptime Main return). No query
text, IDs, focus, keyboard ownership or AX reads. No periodic sampling or
retry. Existing single typeText, full-miso predicates, timeouts and complete
ExploreUITests file remain byte-identical. Workflow retains the numeric file
or an explicit missing-file note. Missing evidence does not prove no receipt.

Atomic writes occur in the diagnostic path and can perturb input timing.
Utility/Main probe order may interleave across events; correlate event IDs.
Storage writes are not proof of rendered text or complete AX value. A wrapped
binding can itself affect behavior, so compare against uncaptured evidence.
No production-enabled feature change or proposed typing workaround.

Every original Library/workflow file reconstructs after removing only these
additions. Actual-head focus must match anchor AND destination source.
No native visual qualification, waiver, publication or merge. Runner init
failure is separate. Source PRs close only after Reviewer confirms the
destination commit; branches kept.
Evidence: https://github.com/melusi-k/ate-ios/actions/runs/43708361930/artifacts/14164353447
