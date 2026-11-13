# Slice4: dormant durable redo and metadata authority

Hosted parent2eabdf034e3ce656d44182043188d6a0922da1c3,
tree894bb4f6d442bf63a01e469b1b131014313e91ce (approved dormant slice2).
No production wiring, cloud calls, activation or schema migration.

## Protocol

RecipeShoppingSyncCommitJournal retains checksummed exact raw recipe/shopping image
and sync metadata under one immutable, pre-provisioned shared personal directory.
The service retains the concrete original AccountWriterGate/lease and holds its
writer effect for every commit/recovery operation, including unwrapped call sites.
Its authorize closure proves current full session, persisted receipt and snapshot
admission agree with the record's owner and ORIGINAL generation. No generation or
owner promotion, receipt stamp, network put or reset is performed here.

Commit order:
1. Encode complete raw after-image and metadata before changing stores. Refuse any
   unresolved intent/temp or foreign/corrupt existing authority. Write/fsync/fullsync
   exclusive-create fixed temp, rename, fsync parent, exact readback of the redo intent.
2. One throwing SwiftData save via existing raw-image restore service, no model
   normalization. Verify through a fresh ModelContext raw snapshot.
3. Fsync/fullsync/rename/parent-sync/readback the durable metadata authority. It is
   the source of truth for stamps/tombstones; UserDefaults is only a projection.
4. Set/readback defaults projection. Retire intent by unlink and parent fsync only
   after revalidating admission AND the required exclusive writer-routing invariant.

Startup after snapshot admission, before ordinary load or new merge:
- Verify envelope digest, version, identities, ordered positions, owner/generation.
- An intact temp-only intent can be durably promoted; malformed/torn temp evidence
  remains closed, never overwritten/deleted by guessing. Conflicting intent+temp
  blocks. An interrupted metadata temp is promoted only when it exactly matches
  the admitted intent's expected bytes.
- Replay the exact local after-image idempotently. Do not repeat cloud puts. Finish
  authority/projection/retirement in the same order. If the intent already retired,
  restore defaults from durable authority, covering asynchronous defaults loss.
- Unknown/foreign/advanced generation, corrupt state, stale lease or unbound writer
  routing refuses before replay/retirement and preserves the evidence.

Directory paths use canonical immediate-parent lstat/O_NOFOLLOW/file-type checks
and existing provisioned-directory assumptions; no hostile same-UID race claim.

## Writer and reset integration boundary

No production caller is installed. The required validateWriterRouting closure is
NOT itself proof that every writer was wired. Final factory must supply it only
when ALL standalone stamps/tombstones and recipe/shopping writes use this same
commit authority under the same original gate. Current staged AppStore helper
still has the earlier non-atomic path and must not be called production-safe.
No retirement/adoption release may be claimed before that integration qualifies.

The component factory clearAllComponent returns the exact personal directory
participant. Final standalone account-wide Clear all inventory MUST append it,
including temporary intent and metadata bytes. The native reset test actually runs
ClearAllLocalData.execute with this component under a real reset gate and verifies
the directory is empty (the existing participant retains its root directory). No production inventory exists yet to bind silently.

## Tests and evidence

Eight native test methods added, all UNRUN:
-13 boundary cuts, actual on-disk ModelContainer save/reopen/replay and idempotence;
-Injected throwing ModelContext-save seam, retained intent and old raw rows before
 replay, then successful fresh-container recovery;
-Unknown/foreign/advanced admission keeps exact intent and old state;
-Unbound writer-routing invariant cannot retire;
-Corrupt temp retains evidence with zero local changes;
-Defaults projection failure retains durable intent/authority, recover on reopen;
-Account-wide component erases intent/authority/temp personal bytes;
-Concrete retained original gate rejects calls after lease invalidation, even when
 callers do not wrap the call themselves.

Tests use real local gate/receipt and an explicit simulated snapshot proof, isolated
UserDefaults suite and actual temporary on-disk SwiftData configuration. They are
written evidence, NOT executed native qualification or real process-kill/fsync/OS
failure proof. No production/backend requests or paid CI.207 Python checks PASS;
diff-check PASS. Existing raw-image restore gains a defaulted throwing save seam
and rollback on save failure; normal archive callers retain the default save.

Reviewer alone publishes/merges. Source PRs close only after Reviewer confirms the
destination commit; branches kept. Food Journal stays OFF; no new UI.
