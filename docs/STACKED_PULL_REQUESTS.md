# Stacked pull request workflow

## Purpose
Use short, reviewable, dependent PRs to deliver larger outcomes incrementally without losing issue ownership, acceptance evidence, or merge safety. Stacking is a delivery technique, not a substitute for issue tracking or release governance.

## When to stack
Stack when a feature has two or more useful, independently reviewable layers with a real dependency (for example, persistence → domain/service integration → UI → acceptance coverage). Keep unrelated work in separate PRs. Prefer 2–4 PRs per stack. Do not split small changes merely to create more PRs. Avoid stacks whose intermediate changes cannot compile or be meaningfully reviewed.

## Required metadata
Every PR body must contain a `## Stack` section with:
- **Stack ID:** `None` for standalone work, otherwise a stable identifier such as `issue-179`.
- **Parent PR:** `None` for standalone or the immediate parent PR number (digits only).
- **Position:** `None` for standalone or one-based `N/Total` (for example `2/3`).

A stacked PR must link its owning issue, name its immediate parent, target the parent's head branch, use the same Stack ID, increment position by one, and remain in this repository. Each PR contains only its incremental diff. The automated validator checks metadata, parent state, stack ID/position, and base alignment.

## Branch and PR conventions
Use `stack/issue-<number>/<position>-<short-name>`, e.g. `stack/issue-179/02-domain`. The root targets `main`; each child targets its immediate parent's branch. Keep branch names stable. Describe what this layer adds, acceptance criteria addressed, parent/children, tests/evidence, limitations, and whether this PR alone completes the issue. GitHub's comparison view should show only the child's incremental changes.

## Review and CI
- Every PR passes all applicable required checks on its exact proposed head SHA.
- Every PR receives independent approvals required by repository rules; a parent's approval does not approve a child.
- Review incremental diffs against declared bases; re-review after material changes or parent rebases.
- Never skip, quarantine, weaken, or bypass required checks to keep a stack moving.
- Run independent work (e.g. isolated UI test shards) concurrently when safe; preserve implementation dependencies.
- If a parent changes, update/rebase descendants in order and wait for fresh checks on each resulting head.
- A child whose parent closes without merging is blocked until safely retargeted and reviewed.

## Merge and issue closure
Merge root to leaves, one PR at a time. Before each merge, verify the parent is merged, the child base is correctly updated, its exact head is current, required checks pass, approvals remain valid, and conflicts are resolved. After a parent merges, retarget the immediate child to `main`, reconcile its branch, inspect the resulting diff, and rerun checks. Changing the base alone is not proof that the diff is correct.

A merged PR does not automatically complete its owning issue. Close the issue only when all acceptance criteria are met (or explicitly accepted as deferred by the product owner), automated/manual/device evidence is recorded, required PRs/follow-ups are merged or explicitly descoped, and project status is updated. Use `Closes #<issue>` only on the final PR if it truly completes the issue; earlier PRs use `Part of #<issue>` or `Relates to #<issue>`.

## Work in progress and throughput
Aim for no more than 3 active stacks per delivery stream and 4 PRs per stack. Prefer finishing/reviewing an existing stack over starting another when review or CI capacity is saturated. Keep blocked stacks visibly blocked and identify the exact dependency. Measure issue acceptance lead time, review time, stack depth, parent-change rework, and blocked time—not PR or merge counts.

## Recovery and exceptions
If a stack becomes stale, too deep, conflicted, or poorly split: stop adding children; identify the last merged ancestor and unique work on each branch; preserve useful commits/tests; rebase/retarget in dependency order; inspect each diff; close superseded PRs only after unique changes are accounted for and replacement work is documented. Urgent hotfixes may remain standalone, subject to normal review, CI, and release controls.

## Pilot success criteria
Run at least one real stack through merge and issue acceptance. Review incremental reviewability, time to first review/merge, CI turnaround, rework after parent changes, and accuracy of issue/project closure. Adjust based on evidence; do not claim throughput improvement from PR volume alone.
