# Food Journal activation, stage 5: raw recovery before adoption

Incremental base e0c3df425ab559c1de46bf9965dfbe60f8ff32c6. Part of #245.

Production admission now has a required raw recovery dependency. It captures the
original receipt under the account gate and obtains one authoritative snapshot if
signed in. No network await holds the flock. Under the original lease it rechecks
full session/receipt, rejects foreign or changed/reset account generations and only
then invokes recovery for the proven owner. Existing local receipt ownership is
used to finish its transactions before a first sign-in can adopt the account.

Recovery runs before reconciliation's archive boundary. A concrete raw adapter uses
UnifiedArchiveStartupRecovery with a no-flock nested lease while the account gate
is held. Strict raw containers are required: no ordinary constructor, migration,
move-aside recovery or empty-store fallback before archive recovery finishes.
After successful recovery the already verified snapshot feeds reconciliation; it
is not fetched a second time. Final retained session/receipt proof still applies.

Tests strengthen existing local/missing-contract checks and add remote-reset
preflight refusal and raw-recovery failure/no receipt stamp/no constructors. Eleven
new native methods cumulative, UNRUN. Diff check PASS. No assertion removals,
longer timeouts, route activation, deployment or data reset.

Pending production binding remains real: strict container opening, canonical path
provisioning, reset/surface quiescence, auth/extension lifecycle and root host. This
adapter alone does not prove process-death recovery or full graph readiness.

Rollback before routing: revert this stage. After routing, preserve recovery records
and canonical bytes; never ignore a failed recovery or delete a receipt to admit.
