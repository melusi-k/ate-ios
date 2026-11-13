# Slice3a: isolated RPC error meanings

Hosted base178afa4eddf5a0fe1a602a479c392a72ee52ee2f. Branch-only,
independent of staged slice2. Native test UNRUN; no production requests.

AccountDataResetService now distinguishes401 unauthorized from403/42501 permission
refusal. PT409 remains a permanent generation conflict. No retry/direct-table
fallback. Permission denial no longer tells the user to sign in or implies expiry.
Both fresh/resuming Clear all coordinator branches explicitly report permission
refusal, without new reset, local erase or retirement of a retained request.

A native matrix covers all three RPC operations and401/403/42501/PT409/missing
contract, exact single transport call and bearer propagation. A second native
coordinator test checks fresh/resuming permission refusal has no receipt publish,
local component construction or replaced retained request. No modified test
assertions.207 Python checks PASS; native compile/execution UNRUN.

This is NOT full slice3 auth handling. Ordinary standalone construction is still
dormant, and staged AppStore401 refresh/re-admission and session-expiry lifecycle
remain unimplemented. Do not claim API compatibility or auth qualification from
this transport delta. No UI/default sync/activation changes; Food Journal OFF.
Reviewer alone publishes. Source PRs close only after Reviewer confirms destination
commit; branches kept.
