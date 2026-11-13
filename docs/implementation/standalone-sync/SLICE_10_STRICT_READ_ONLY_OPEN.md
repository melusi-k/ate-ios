# Slice 10: pre-admission strict read-only open

Dormant StoreRecovery.openExistingReadOnly is distinct from legacy open(). It
requires an existing regular canonical nonsymlink store path. It invokes exactly
one ModelContainer factory with allowsSave:false and CloudKit disabled, turns off
main-context autosave and propagates failures. No moveAside, new store, in-memory
fallback, diagnostic singleton, repair, export, receipt or defaults changes.

The returned observer container must be released before admitted resources opens
a writable graph. Raw inventory is read through existing throwing raw capture,
never AppStore compactMap/empty adoption. AppStore observation uses the immutable
readOnlyPendingAdmission policy. completeRecovery already refuses that policy or
RecipeShoppingSyncOwner, so legacy metadata reset/export cannot run on it.

Three native tests UNRUN: corrupt one-attempt refusal with exact evidence retained;
missing/symlink no factory call; real disk SwiftData reopen with exact raw bytes,
position and createdAt retained and an attempted save refused. Does not claim SQLite
read opening cannot create/touch bookkeeping sidecars; allowsSave is not a filesystem
snapshot. ModelConfiguration API sources:
https://developer.apple.com/documentation/swiftdata/modelconfiguration/allowssave
https://www.hackingwithswift.com/quick-start/swiftdata/how-to-configure-a-custom-modelcontainer-using-modelconfiguration

Default legacy launch remains unchanged and this seam is NOT production-wired.
