# Dormant strict runtime factory (#245)

Activation in this slice: OFF. The owner's enable-and-validate direction is
the follow-on goal, not a launch approval. This branch adds no production caller and does not switch any
screen, account, archive, reset, background job, intent or watch route.

`FoodJournalRuntimeFactory.bind` accepts an already-open caller-owned container.
It never opens/reopens a store, recovers corruption, falls back to memory, seeds,
cleans up or runs diary migration. The owner must provide defaults, a goals
repository (including its owned storage), writer boundary, separate migration
and repair directories, and restore callback. Runtime wraps that goals storage
with the same writer boundary. Defaults identity must match.

Admission requires `.ok`, all configurations disk-backed and writable, the
JournalEntry/JournalMealPayload schema, no unsaved main-context work, explicit
file backup directories, and successful committed reads. Invalid meal pairing
throws rather than becoming an empty diary. Recovered/fallback/unavailable
states remain blocked. Refusal does not save, roll back or delete user records.
Successful binding disables main-context autosave; isolated journal readers and
writers preserve the existing transaction model.

Runtime CookingHistory now inherits the supplied boundary. Its normal record,
verified record and clear paths all enter that boundary. Existing legacy/shared
callers keep their prior default boundary. A refused effect must leave history
and defaults unchanged.

This factory does not prove the supplied owner is a complete account domain or
that a disk store is healthy forever. It does not own container opening, media,
archive/reset quiescence, generation receipts, or retirement of existing global
consumers. Those remain activation gates. The restore callback and writer
boundary must be real owner implementations before activation. No production
readiness claim follows from constructing this dormant runtime.

## Evidence

Six additive native fixtures cover explicit binding/no migration, unavailable
and memory refusal, pending edits/mismatched domains/invalid paths, read-only
and partial schema, unreadable meal pairing, and boundary refusal before binding
and after binding (including cooking history). All six are added to the existing
required full-unit union. No existing required entry or assertion is removed.
Python source guards keep this seam dormant and prevent recovery/shared-domain
fallback. Native Swift build and execution require exact-head CI; grammar checks
are not typechecking. There is no visual change in this packet.
