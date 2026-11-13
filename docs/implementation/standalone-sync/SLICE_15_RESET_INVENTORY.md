# Slice 15: explicit standalone personal erase inventory

Dormant composition, no cloud request or local erase executes on construction.
Required retained domains/paths, no singleton/fallback path lookup. A complete
JournalLocalReset (including adoption preservation) erases existing Journal bytes
WITHOUT activating Food Journal. Recipes require a real container or erase fails.

Standalone additions cover raw recipe/shopping rows; SyncMeta/stamps/tombstones
and all known personal app/shared defaults in authority, legacy standard and shared
domains; entire dedicated sync redo/authority and legacy adoption-preservation
directories; recipe AND Journal StoreRecovery Backups; recovered recipe JSON exports;
known temporary data/shopping/beta/diagnostic exports; shared inbox orphan media;
shared AND app-only cover files; personal archive txn-* evidence including malformed
transaction directories; QA mock-server cache. JournalLocalReset contributes Journal
rows/raw payloads, media, goals file, diary/cook defaults, legacy/corrupt backups and
Journal adoption preservation. All components independently erase and verify empty.

Selective roots (Documents/temp/archive-control/cache) use only app-owned names,
not paths from payloads, and leave unrelated siblings/minimal control alone. Child
symlinks unlink without following; symlink/noncanonical roots refuse. Dedicated
personal directories erase all contents, not only decoded/readable entries.

Minimal reset/generation/epoch/ready/lock control, Keychain account and subscription
remain. Reset gate rotation invalidates old ready epochs. No rollback personal copy.
Caller must quiesce all producers/unmount old graph, hold actual reset gate and bind
real awaited notification/LiveActivity/Spotlight/widget/watch cleanup. In-memory
CoverStore/singleton caches must be retired/cleared by that host, not falsely claimed
erased by filesystem cleanup. Directory/default deletion uses existing erase
primitives' verified-empty semantics; this is not a new crash-durable unlink proof.

Two native tests UNRUN: full local fixture retains only control/unrelated siblings
while personal rows/redo/backups/defaults/inbox/covers vanish; selective root-link
refusal and child-link unlink safety.207 Python PASS. Actual production URL/domain
binding and end-to-end account Clear all qualification still required.
