# Account assertion-state capture only

Base d88bf6be4dd63f8eed3f91e147d28de92478640a. Native UNRUN.
Final Finish now passes recorded confirmation and unique Done, taps Done,
but Cook mode remains absent. This differs from bc45's missing-Done test
flow. Tracker month predicates repeat older532line58/67 failures, while
535e1ed/534bc45/537 pass the named case. Slow AX reads can consume a waiter
without proving state was unchanged. No product cause is established.

DEBUG/UITesting/per-case qaAccountAssertionDiagnostic only. Up to32numeric
console events per process. Phase1previous tap receipt,2next receipt,
3displayed-month state change,4timezone reset notification,5locale reset;
values are month epoch timestamps. Phase19completion offer set,20Done
closure received,21sheet onDismiss,22exit entered,23exit returned,
24root onExit entered,25cookTarget nil assigned. No recipe/session/user
payload. No polls, retries, sleeps, timeout or allowance changes.

Add before/after/end Done screenshots and a final Cook query description;
add after-month-tap screenshots and month query descriptions. Existing
single taps and all original assertions remain. AX debug descriptions can
contain only query chains, not a resolved hierarchy. Extra captures can
perturb timing and may themselves stall; no claim of a wall-clock bound.
Numeric console output also may perturb. Missing output is unverified.

Entire original modified source files reconstruct after reversing only
capture additions. Earlier Finish whole-file guard composes reversal first,
then checks its unchanged original baseline hash. Native compile, pixels,
Tracker state transitions and completion-dismissal remain unqualified.
Ingredients gathered-count query, timer snapshot timeout and runner startup
failures remain separate open reds. No waiver, publication or merge.
Source PRs close only after Reviewer confirms destination commit; branches kept.
Source https://github.com/melusi-k/ate-ios/actions/runs/43708207049/artifacts/14165297184
