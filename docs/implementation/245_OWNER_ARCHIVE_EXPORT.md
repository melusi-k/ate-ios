# Owner archive export (#245, step 3c)

Dormant dependent capability after disk resources/admission. No Settings or
AppStore callback is installed in this slice. No production write/deploy.

Export validates owner proof, then runs existing diary/goals migration under the
owner's ordinary boundary before no-write snapshot. The snapshot captures the
actual owner's Journal, goals/defaults/media and supplied recipe container while
the account gate holds its own nested archive root. No lock crosses the async
media read. Before bytes can escape, owner/epoch/archive generation and unresolved
recovery are checked again. A changed generation or stale owner refuses export.
Snapshot/validation do not advance archive generation; actual migration effects
use the existing ordinary boundary and may advance it before capture.

Main still lacks lossless recipe-association archival. Export therefore refuses
nonempty or unreadable association sidecars rather than presenting a falsely
complete personal backup. This preserves those bytes and avoids enabling recipe
linking until its archive contract is implemented. No associations are erased.

Four additive required native tests cover owned reflection/media bytes, writer
epoch rotation during the unlocked async phase, archive generation change during
that phase and unarchived sidecar refusal before migration. Prior required union
57 -> 61. 197 Python tests, two Swift grammar checks and diff-check pass. Native
build/typecheck/execution UNRUN. Same-process tests are not process-death proof.

Archive import, quiescence, final lazy graph and production UI installation remain
pending. This capability does not prove the supplied recipe container is the only
owner; final composition must use the recovered resources and original admission.
#245 remains open. #523 workflows/anonymous sign-in remain OFF.
