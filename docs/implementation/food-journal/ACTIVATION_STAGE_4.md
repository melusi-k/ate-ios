# Food Journal activation, stage 4: actual defaults owner and import reload

Incremental base dadc4ede18d38a5a6fe89d59d3d701b4ac8a70cf. Part of #245.

AppStore settings, timer preferences and sync metadata now load/save through the
injected runtime's defaults domain when canonical, with standard defaults unchanged
for legacy callers. Previously the runtime's cook session and archive used one
domain while AppStore read/wrote another. Onboarding remains installation-scoped.

After a successful unified import, AppStore reloads recipes, shopping, settings and
timer preferences and refreshes its comparison snapshots under its writer boundary.
This is a separate covered unit after the import's own committed generation; it is
not an extra generation inside the import transaction. Failure after disk commit
throws honestly rather than falsely reporting refreshed UI or rolling back data.

A new native test covers isolated settings construction/write/reload and truthful
reflection-only import counts. Nine new native methods cumulatively, all UNRUN.
Diff check PASS. No removed tests/timeouts, production route switch or backend work.

Remaining startup recovery ordering must be completed before routing: reconciliation
currently stamps through the archive boundary, which intentionally refuses unresolved
archive transactions. A raw recovery callback merely placed after reconciliation
would never run in that state. Do not ship such a callback as proof of recovery.
The production orchestration must establish authoritative account/receipt identity,
run strict raw archive recovery under the account gate, then final reconciliation
and ordinary constructors, with every post-await identity rechecked.

Rollback: revert this stage before routing. After a real import, preserve committed
canonical bytes/recovery controls; restore the previous view layer or show recovery,
never delete imported data to simulate rollback. Earlier stage caveats still apply.
