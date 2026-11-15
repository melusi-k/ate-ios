# CookPlan local cancellation patch-forward

Base latest #534 fda9dd649bf8efd9a50f5e85e7e27b51009e499a, including the
Settings diagnostics heading correction. No remote publication or merge.

## Evidence and diagnosis

#532 aafed988, run43749134596 job132919057662: the no-reminder CookPlan
journey fails at line48 after44.983s. Cancel tap40.20s, underlying recipe.plan
exists42.28s, next tap computes hit point{-1,-1}, then old cancel row still
exists43.71s. The previous #534 log has the same boundary at line43: Cancel
tap38.30s, recipe.plan exists54.00s, invalid hit point64.71s, cancel row
still exists66.62s, final failure91.588s. Other retained executions of this
journey pass (62.420s,58.802s,45.102s), so compare the actual boundary rather
than treating every CookPlan failure as startup failure.

Source deletes and verifies local plan first, then awaits queued OS removal
and verification before updating any view state or dismissing. Its existing
state continues advertising the removed saved plan while OS cleanup is
pending. This is a product-state/async-boundary defect. The existing test's
post-cancel wait only proves underlying recipe.plan exists, not that the sheet
closed. Its attempted reopen is not proven by the failing logs. No retained
failure establishes that plan bytes survived cancellation or that a new sheet
reloaded the plan.

## Change

New cancelLocally mirrors the existing saveWithoutReminder architecture:
- Persist and verify local cancellation synchronously. Failure throws before
  registering notification cleanup, preserving error visibility.
- Register cleanup in the SAME enqueue before returning. Existing generation,
  serialization, removeAndVerify and await semantics are unchanged.
- Return a task that awaits verified OS cleanup and reports failures.

The real sheet clears existing state and dismisses after verified local
removal, without waiting for notification XPC. Immediate copy says only
"Cooking plan removed", not that a reminder is removed. Cleanup failure warns
that reminder removal could not be verified. No false OS success. Existing
async cancel remains unchanged for callers requiring awaited verification.

## Verification and limits

CookPlanUITests, CookPlanNotificationTests and CookPlanTests are byte-identical
to base. No assertion, selector, wait, timeout, retry, workflow or allowance
changed. Existing owner frozen-hash contract strips ONLY the strict exact new
addition before checking its SAME original hash. Three new Python contracts
check inverse source, commit-before-enqueue-before-return ordering, honest
sheet state and all original fixture bytes.

Four new native unit cases cover local commit before suspended OS read,
retained-reminder error without resurrecting plan, unreadable local bytes
without OS cleanup, and old suspended add/cancel/later re-enable ordering.

Native build/typecheck, XCTest, simulator/device and actual pixels UNRUN for
this patch. Require original no-reminder UI named pass plus the new unit tests
on exact integrated head. The unchanged UI case alone is insufficient proof
of actual reopen after cancel: independently inspect actual sheet dismissal,
reopen and relaunch showing no saved plan, and a failed/suspended reminder
cleanup path with truthful copy. Do not call a source-test pass acceptance.

Keep branches. Source PR closes only after reviewer confirms destination commit.
