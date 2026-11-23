# Separate nutrition verdicts without raising a timeout

Base: published #660 head 1b33291084fafe1bb9d21c4da96d5fa5c803a291.

All three preceding build-nutrition cancellations have a GitHub annotation stating
that the configured 45-minute job maximum was exceeded. Account-cooking completed
with failures rather than cancellation. The 55-minute observed wall times on two
nutrition jobs include time beyond the configured limit; they are not a new budget.

Sources:
- https://github.com/melusi-k/ate-ios/actions/runs/45141909439/job/137581771174
- https://github.com/melusi-k/ate-ios/actions/runs/45155839151/job/137628468762
- https://github.com/melusi-k/ate-ios/actions/runs/45159545718/job/137641126120

## Candidate

- nutrition-units keeps the original App Clip build, App Clip URL contract-test
  command, full AteTests command, required-unit verifier and artifact retention.
  Each is executed once, not once per UI shard.
- nutrition-ui has three disjoint selections: CookPlan plus normal-text nutrition
  accessibility audit; NutritionDiary; NutritionGoals. The union is the original
  selection. Existing named-pass guards follow their class. No new smoke duplicate.
- Each Mac worker retains a 45-minute cap and the same 240/480-second test policy.
  Matrix fail-fast is false and max-parallel is 1. No retry or skip is added.
- build-nutrition becomes the original-name Linux aggregate. It requires both the
  unit worker and the whole three-worker UI matrix to succeed. Failed, skipped,
  missing or cancelled results are not passes. Existing compile and qualification
  contexts, docs-only routing and unrelated regression jobs remain intact.
- Each UI worker builds its own exact checked-out head. No cross-machine test-bundle
  transfer is introduced. This repeats setup/builds and can increase Mac minutes
  and queuing. This is not a faster/cheaper claim or an approval to spend.
- CookPlan ledger capture precedes attachment export. The shard records raw output,
  producer/pipeline exit status, export status, xcresult, lifecycle/query evidence
  and attachments in a shard-specific artifact immediately after its selection.
  Export failure is visible and fails the worker; upload still runs under always().
  A hard job kill can still prevent tail collection. This patch does not promise
  evidence from a process killed before it can export.

## Checks and remaining acceptance

New tests inspect the real YAML, prove selector union and empty intersections,
retain every named guard, compare App Clip/unit commands and downstream contexts
with the exact base, execute 36 aggregate result combinations, parse every new Bash
body and reject altered-workflow inverse mutants. Old inverse endpoints remain
unchanged. A whole-workflow exact inverse feeds historical workflow guards, while
new tests separately check the new workflow semantics. Caller inventory is 26
XcodeGen jobs because one Mac worker definition was added.

Python checks are not native proof. No production app, native tests, UI tests,
project configuration or per-test assertions change. The next new-head run must
supply its own unit, three UI and downstream regression verdicts. Existing account,
Journal and other UI reds are not repaired or excused by this partition.
No workflow dispatch or unchanged-head rerun is part of the packet.
