# Slice7: post-admission strict open, replay and raw inventory

Stacked on re-pinned authority binding from hosted read-only6b72f860c453b4cdf1d9eb8b0842e2deb6acac78.
Authority runtime delta remains separately reviewable. Dormant factory,
no AteApp/production switch, no Food Journal activation.

Owner exposes makeCommitJournal/admittedReceipt and full-bound-session validation
only through its retained admitted capability. No new gate/epoch/receipt inferred
from defaults. Resources.open requires that proof before any ModelContainer factory
runs. Strict open failures propagate, with no StoreRecovery move-aside, retry,
replacement or in-memory fallback. Main context autosave disabled.

After open, journal recovery/projection completes under original gate before raw
inventory or AppStore binding is returned. Raw inventory captures exact persisted
recipe/shopping bytes including unreadable rows, plus metadata. It validates known
matching owner and every decoded identity/stamp without discarding malformed rows
as empty. This slice refuses missing metadata/unknown owner even for an empty raw
store. It never stamps/adopts, preserves backups or changes a receipt. Legacy
adoption/preservation remains separate. No generation advancement.

Three native tests UNRUN: no open before admission/full-session match and exactly
one throwing strict open without fallback; malformed raw/unknown/missing owner
never empty adoption; actual pending redo after store save replays through strict
fresh-container resource open before inventory/binding. Existing protocol tests
supply the wider crash-boundary matrix.207 Python PASS; diff-check PASS.

validateWriterRouting is still a required final-construction invariant, not proof
that all extensions are wired. Production call site must not supply an empty
closure while shared/extension writers bypass authority. Tests deliberately use
isolated proof closures and no production claims. Auth remount, signed-out local
mode, legacy preservation/adoption, shared writers and reset inventory remain.
Reviewer alone publishes/merges. Source closure requires destination confirmation;
branches kept.
