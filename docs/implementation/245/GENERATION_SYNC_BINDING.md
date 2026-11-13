# Activation slice: generation sync binding (OFF)

Union starts at graph62d92f8 and merges backend841c14e/conflictfb10298f with ordinary
merge, no rebase. AteApp remains unchanged; no production activation or deployment.

Admitted FoodJournalAppGraph now injects retained GenerationFencedSyncService into
AppStore before load. Injection works with ordinary auth, not just injected mocks.
A sync cycle pulls atomic snapshot+capture, checks persisted owner/generation receipt,
merges only validated rows and pushes using the original capture. No direct-table
POST fallback. Captures are single-use; AppStore abandons them on every sync exit,
including local publish failure. Concurrent syncNow calls are refused while syncing.

A snapshot ahead/behind the receipt or PT409 blocks the service, consumes the capture
and invalidates the durable writer epoch. Original graph writers then fail their
retained lease. No new lease, stamp promotion, implicit refresh or retry occurs.
Three native tests cover original capture, single-use, advanced snapshot block and
partial-put stop/invalidation. Native compilation/tests are UNRUN; Python/static
checks are not runtime proof.

Remaining activation work: mount observable blocking conflict state and destroy old
graph; durable block across relaunch; full auth-session invalidation/remount; complete
all extension/deferred writers and quiescence; immutable shared paths, full reset
inventory/Settings reset binding and safe status recovery. This slice's conflict
property alone is not a shipped recovery screen. Activation stays OFF until those
are bound and exact-head native/visual/device proof is available.
