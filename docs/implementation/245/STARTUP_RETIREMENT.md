# Activation slice: startup retirement (OFF)

Builds on durable conflictc4a3c051. `ResetAwareStartup.retire(reason:)` drops the
owner's ready graph and permanently blocks that startup owner. A run identity is
captured before resume/snapshot work; late success or failure cannot replace a newer
terminal block. This does not rely on Task cancellation being observed.

There is no implicit restart. A replacement owner must perform reset recovery and
full owner/generation reconciliation again. The caller must FIRST install a durable
writer fence and stop all producers; this method is not a lock, auth commit, task
join or complete quiescence. Retained references outside startup can keep the old
graph alive, so callers must clear static AppStore.current, UI roots, bridges and
producer callbacks as part of their own retirement inventory. This slice does not
claim to have bound those production paths.

Three native tests cover release of ready graph, no implicit restart, late reset
resume, and late admission success/failure. Native tests/compile UNRUN. No view or
AteApp route changed. Existing generic blocked view remains the presentation.
