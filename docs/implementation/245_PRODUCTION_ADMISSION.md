# Dormant production admission (#245, step 3b)

Dependent on strict disk-recovery resources, authored fresh on #530. No production
caller or RPC invocation is installed. The snapshot remains an injected read.

The retained admission controller ties gate, reset control and generation receipt
to one actual control root. Signed-in startup must obtain a current snapshot;
contractMissing/transport failure is not generation zero and causes no personal
open, recovery, preservation or receipt stamp. Signed-out admission never calls
the server. A pure preflight rejects foreign accounts, advanced/regressed/invalid
generations and missing signed-in generation evidence before raw recovery.

The original lease and full AuthSession (including token identity) are rechecked
after the snapshot await, during raw recovery authorization and inside the final
reconciliation stamp effect. Raw archive recovery runs under its old receipt
owner before local-to-account adoption. Legacy preservation and receipt stamping
reuse JournalInstallReconciliation only after recovery. A final expected receipt
check closes the reconciliation await before proof publication. Binding and
validation require unchanged session, receipt/control and original lease.

No automatic erase, replacement lease, signed-in offline fallback, auth activation
or production write/deploy. Once bound, auth lifecycle must rotate the existing
gate before account/session replacement; full quiescence/graph integration is
still a later required packet, not supplied by this proof object alone.

Five additive native fixtures cover pure ownership/generation policy, signed-out
preservation/admission, missing signed-in contract, same-account token change
across await and final proof/lease mutation refusal. Required union 52 -> 57.
196 Python tests pass. Resources, admission and tests have grammar checks; gate
parsing excludes its unchanged external flock declaration. Native typecheck,
build and execution remain UNRUN. No visual change/pixel claim. #245 remains open.
