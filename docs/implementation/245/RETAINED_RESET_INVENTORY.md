# Activation slice: retained Journal reset inventory (OFF)

Builds on57d376e0. `FoodJournalAppGraph` now retains a concrete JournalLocalReset in
AppStore using the graph's actual Journal/defaults/goals, injected migration and
repair backup directories, consumer preservation directory and exact journal store
configuration URL. Journal's current media writer still uses JournalStore.mediaDir,
so this slice names that actual path explicitly. It does not pretend an unrelated
injected archive-media directory has changed the Journal media writer.

The convenience initializer that reconstructed reset paths from global defaults was
removed. Unified local wipe refuses BEFORE legacy recipe/shopping erasure when its
retained inventory is absent or points at another runtime's Journal/defaults.
Existing sign-out/delete-account paths still need full lifecycle/reset binding; this
change only prevents their local Journal phase from silently missing custom backups.

Native fixtures now bind explicit sandbox-owned reset inventories instead of reaching
real process-default backup/media paths. Existing wipe assertions remain intact. A
new test proves missing inventory preserves recipes/meals before any local erase;
graph test assertions pin injected store/backup/preservation paths. Native compilation
and tests UNRUN.191 Python tests PASS, not native reset proof.

This is NOT the full account-wide component list. Recipe store backup files, recovery
exports, Covers/Inbox directories, archive before-images/staging, standard/shared
allowlists, sync metadata and system surfaces still need an explicit inventory and
quiescence. Settings still runs its old library-only callback and must not advertise
account-wide erasure until those bindings are complete. No app route flip/deployment.
