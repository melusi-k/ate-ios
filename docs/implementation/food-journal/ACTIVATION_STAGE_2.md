# Food Journal activation, stage 2: retained admission proof

Incremental base a7e48978ea3394bed833a6ff6b4b046390e05781. Part of #245.
Production routing remains unswitched. No owner scope decision is assumed.

FoodJournalProductionAdmission binds the existing install reconciliation to stage 1.
Signed-out device-local adoption preserves original legacy bytes and stamps its
stable local receipt without calling the snapshot closure. Signed-in admission must
obtain a verifiable account snapshot; missing contract remains blocked before any
ordinary resource or AppStore constructor. No generation-zero guess or conversion
of a signed-in account to a local identity is introduced.

The retained proof records original lease, full AuthSession and exact receipt after
reconciliation. The synchronous final construction check revalidates these under
the same account gate. It is read-only and never enters an empty archive effect.
Session change, receipt change or pending reset blocks construction. This proof does
not replace lifecycle invalidation on every later auth transition, which remains
part of production wiring.

Three additional native tests cover local/no-RPC admission, signed-in missing
contract/no ownership fallback, and post-reconciliation session/receipt changes.
Existing required tests remain; only these new method names are appended.

Reviewer reported production contract absent to main. Choosing device-local-first
versus backend-first is pending outside this stage. This code supports either:
local users do not need the contract, signed-in users remain gated. Do not mount
this gate in front of Library/Cook for all users until that direction and full
participant readiness are resolved.

Rollback: revert this incremental commit before routing changes. If later enabled,
preserve receipts, adoption backups and canonical records; never erase control or
restore stale legacy keys. Stage 1's rollback conditions still apply.

Verification: git diff --check PASS. Native build and all six new graph/admission
tests UNRUN. Prior stage's 155 Python checks covered infrastructure, not Swift
runtime proof. No production mutation, merge, deployment or activation performed.
