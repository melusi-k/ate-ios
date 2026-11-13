# Activation slice: durable conflict fence (OFF)

Builds on generation sync57720651. No app route activation or production action.

Sync's permanent-generation-conflict callback now installs a durable, non-personal
`writer-generation-block-v1` marker under the same account gate before rotating the
writer epoch. Both old effects and new admissions refuse while that marker exists.
A second gate instance or a relaunched process cannot obtain a new writer lease.
Normal auth epoch rotation does not clear it. Ordinary Clear all also refuses; it
must not erase unresolved conflict control or pretend that reset is recovery.

There is deliberately no remove/unblock API in this slice. Safe recovery requires
quiescence, verified current-account snapshot, explicit local-data policy and a new
qualified graph before any future marker retirement is designed. Startup currently
shows its existing generic blocked/failure state, not a finished recovery journey.
The visible graph still needs lifecycle unmount/conflict-state binding.

In-process refusal is set before fallible IO. If persistence/lock fails, the existing
instance stays blocked and sync reports failure, but durable cross-process protection
is NOT claimed. Activation host must unmount and stop producers, not keep an editable
old graph after this error. Immutable ancestor provisioning and full extension gate
participation remain required. This marker does not fix ungated legacy writers.

Added two native tests for cross-instance/relaunch refusal, normal epoch rotation
not clearing the fence, reset refusal, and corrupt/symlink marker rejection. Native
compilation/tests are UNRUN here.191 existing Python tests PASS, not native proof.
