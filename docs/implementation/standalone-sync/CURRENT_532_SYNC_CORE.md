# Standalone sync core on current532

Base4772d94b. First narrow integration slice from prior standalone chain,
not an activation or build441 upload completion claim. Contains snapshot-admitted
owner with cancellation/token/session/generation checks, pure staged merge and
durable redo journal. Current532 AppStore, production/raw recovery composition,
reset/writer boundaries, host/auth lifecycle and shared producers are unchanged.
No ordinary upload callsite or migration is installed and no backend is mutated.

Owner core from9d0d9fbc, stage/journal and tests from686565cd. Later owner's
resource/shared graph factories intentionally excluded until dependencies and
host integration are reconciled. This is not a selectable feature toggle; default
ON policy applies to finished safe feature integration, which remains incomplete.

Archive raw-image restore gets only an injected save seam with unchanged default
save and rollback-on-failure. Needed to test actual save failure/crash checkpoints.
All existing full-unit requirements retained; new core test names appended.
Native SwiftData tests, device restart/disk durability and cloud upload UNRUN.
