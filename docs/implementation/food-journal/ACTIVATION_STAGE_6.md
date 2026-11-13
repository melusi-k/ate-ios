# Food Journal activation, stage 6: strict retained disk resources

Incremental base 73f0ce735bec348111631d7d152b4c5082244a1a. Part of #245.

FoodJournalDiskResources supplies actual raw SwiftData containers to the recovery
adapter and retains those exact containers for ordinary graph construction. It
opens only inside the original account gate after admission preflight. A failed
open/recovery throws, never moves aside the store or supplies an empty fallback.
Existing recipe and named AteJournal disk configurations are preserved by default.
The shared control directory remains an explicit required dependency.

Main contexts use explicit saves so autosave cannot bypass the account/archive
transaction boundary. This is transaction policy for the new admitted graph, not
a proposed cause/fix for the unrelated unproven #518 timer trap. JournalStore is
injected from the exact recovered container, with no second open/seed operation.

Two native tests cover resources unavailable before recovery, same-container
retention, owner change refusal and stale-lease/no-open behavior. Thirteen new
native methods cumulative, all UNRUN. Diff check PASS. No native build/device/
power-loss evidence or production route switch. Existing tests remain unchanged.

Still required: immutable shared control-path provisioning, whole reset inventory,
system-surface quiescence, auth transition remount and extension startup install,
and the actual AteApp lazy root route. The current strict opener intentionally
does not run legacy image-prompt cleanup outside a covered maintenance unit.

Rollback before routing: revert this stage. After routing, keep the same disk paths
and canonical records/recovery evidence. Do not reopen a fresh legacy store or
move corrupt stores aside as a rollback shortcut.

Source-review correction after this stage: archive recipe participants intentionally
skip contentless cards. Consumer counts must come from actual before/after store
snapshots, not incoming IDs. The next correction commit fixes counts and gives the
roundtrip test a real ingredient, plus adds a contentless-card/no-false-count test.
