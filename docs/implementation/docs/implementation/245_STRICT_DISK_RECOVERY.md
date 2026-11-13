# Strict disk recovery resources (#245, step 3a)

Fresh on reviewed #530 tree c3fe799f, independent of the step-4 consumer packets
and the old standalone candidate. Dormant: no production call site or activation.

FoodJournalDiskResources requires explicit disk configurations, domains and owned
locations. It rejects memory/read-only, mismatched Journal URL and overlapping
inventory paths. No StoreRecovery, move-aside, fallback empty store, cleanup,
seeding or diary migration. Corrupt raw stores throw; recovery evidence remains.
Successful binding uses the same recovered container and original admitted lease.

The account gate adds withArchiveRecoveryLease. The nested archive lease comes
from the gate's own private directory while its account flock is held. Callers
cannot substitute a second control root. This raw recovery entry precedes the
ordinary archive boundary, which intentionally blocks unresolved transactions.
It runs UnifiedArchiveStartupRecovery, including its existing committed-history
completion rules, before publishing retained resource references. Raw store
opening may create/migrate storage, so preflight authorization runs before it.

Both recovery and binding require explicit synchronous authorization callbacks.
This slice does not supply those proofs or infer owner authority from strings.
The next admission packet must verify receipt/session/remote generation, recover
under the authorized old owner, then reconcile and revalidate before bindOwner.
Recipe-container access is also tied to the original gate/lease. Resources are
never returned after a failed recovery or stale/foreign admission.

Five native fixtures cover refused identity before personal open, durable
reflection/legacy-byte preservation, corrupt bytes without replacement, foreign
owner/rotated lease refusal and same-gate raw recovery. Required union 47 -> 52.
195 Python tests pass; grammar checks pass for resources/tests and gate code with
the existing external @_silgen_name flock declaration excluded from parsing.
Native typecheck/build/execution is UNRUN. Same-process reopen is not physical
process-death evidence. No pixel change or visual acceptance claim.

Lexical inventory checks do not claim hostile same-UID filesystem/symlink safety.
Quiescence, production identity proof, archive consumer binding, generation-fenced
sync and UI graph installation remain unfinished. #245 stays open. No production
Supabase write/deploy, #523 workflow or anonymous-sign-in activation.
