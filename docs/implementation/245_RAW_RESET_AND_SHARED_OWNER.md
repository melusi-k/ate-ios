# Raw reset and captured shared owner prerequisite

Child of 83d6209f. Source only, activation remains OFF. Final root integration and
all native/pixel gates remain outstanding. No production backend or SQL operations.

## Shared writes

Do not swap the installed shared boundary to a mutable current-graph reference.
That could let a delayed old task use the replacement owner's lease. Instead,
SharedWriterBoundary can carry an immutable owner in task-local context. Child
Tasks inherit it; captured consumer tasks explicitly enter their original owner.
The actual local owner captures its shared adapter around synchronous effects.
The app can install `requiresCapturedOwner` once before ordinary construction:
no owner context then means refusal, not fallback or a late owner lookup. Extension
processes retain their standalone gate installation. No test reset is used in the
production route. Final root must supply the actual boundary to its consumer task
registry and establish the context for UI callbacks outside a writer effect.

## Raw reset inventory

FoodJournalResetInventory has separate unopened and retained-container modes.
Startup resume must use unopened only before any ordinary container is opened;
retained mode requires actual editor retirement and task drains. Neither mode opens
stores, migrates, repairs or calls global personal singletons.

Inventory includes recipe/shopping and Journal bytes, all selected standard/shared
personal defaults, personal sync metadata, goals, Journal media, diary backups,
adoption preservation, covers, share-inbox media, recovered recipe exports and
backups, corrupt goals backups, and active AND retired archive personal recovery
records. The latter retain complete before/after images and are personal data even
when named `.resolved-*`. Exact UUID record names are required; malformed recovery
names fail closed. Minimal lock/epoch/generation/receipt/reset control is retained.
Credentials/account and subscription identity are retained for Clear all. No full
UserDefaults-domain wipe or whole-control-directory deletion exists.

Paths are explicit; destructive roots cannot contain control or selected-artifact
directories. No-link ancestor checks guard selected paths and unopened store paths.
Every component erases and then verifies under the supplied reset validator.
System surfaces and reset sequencing remain the final root's responsibility; this
inventory alone does not claim notifications, ActivityKit, Spotlight or watch state
were cleaned. It also does not authorize an erase by itself.

## Verification

Four native regression methods added to required manifest (88 to 92), covering
old-owner continuation after await under a replacement context, nested owner
capture/default refusal, complete unopened personal-byte inventory with retained
control, and gate/malformed-recovery failure. Native tests/compilation UNRUN.
Python source suite and grammar checks run locally; SharedWriterGate's original
file-level parser defect at its C symbol declaration remains unchanged, so the
changed SharedWriterBoundary class is parsed in isolation. This is grammar only,
not Swift typechecking. Final production binding and pixels are not yet ready.
