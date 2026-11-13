# Slice 11: explicit shared-boundary retirement/remount

Dormant additive APIs. Existing initial install semantics and legacy defaults are
unchanged. retire() waits behind the boundary's existing synchronous effect lock,
refuses if called from inside its own active effect, and permanently rejects all
future effects including old async callers retaining that exact boundary object.

replaceRetired compares the exact installed previous identity, requires irreversible
retirement, refuses same/legacy/retired next, and atomically swaps only that slot.
No boundary state lock is taken while installLock is held, avoiding a lock inversion
with an old effect reading .current. An independently retired new candidate may be
installed by a race but cannot write. This is fail-closed, not a liveness guarantee.

This alone DOES NOT retire a central owner, rotate a durable epoch, validate a new
session or replay redo. Final composition must retire old shared boundary BEFORE
old owner retirement/epoch rotation, and install only the newly admitted/replayed
owner-backed boundary. Existing direct initial install remains one-way. Old extension
processes still require the common durable account epoch and redo readiness check.

Three native tests UNRUN: exact retired replacement and stale capture refusal;
nested retirement refusal/idempotent permanent retire; wrong identity, legacy,
same object and retired next refusal.207 Python PASS. No production wiring.
