# Retained AppStore reflection admission (#245)

The injected AppStore path previously constructed CookedJournalReflectionStore
without the runtime writer boundary. That store directly saves a ModelContext,
so JournalStore's own boundary did not protect the reflection write. This could
persist a reflection after the owner refused, then fail only during outbox ack.

The injected path now asks its existing runtime for the retained reflection
session. This binds reflection saves and outbox acknowledgement to the runtime's
same boundary. Legacy non-injected behavior stays unchanged. Existing retained
sessions are reused, preserving acknowledgement-pending retry and draft rules.

One additive required native test enters through AppStore.requestCookedReflection,
revokes owner admission, confirms no reflection/ack is written and the draft and
exact event survive, then permits a retry and verifies one reflection, no queued
event and no meal. Prior required union 50 -> 51. 196 Python tests pass; two Swift
grammar checks and diff-check pass. Native typecheck/execution remains UNRUN.

No production graph is installed or activated, no new UI or backend effects are
introduced, and cooking still does not imply eaten food or recorded Health state.
This is a step-4 consumer boundary correction, not full #245 acceptance/closure.
