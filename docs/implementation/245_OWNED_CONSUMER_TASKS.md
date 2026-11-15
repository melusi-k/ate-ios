# Activation prerequisite 1: captured-owner tasks

Base factory branch 79636cf38ab4d8b350bcaf73a14577580705b4f8.
Source only. No production install or ON flag in this prerequisite. No #523,
anonymous sign-in or production backend operations. The final activation packet
must not ship until the remaining integration and native gates pass.

FoodJournalConsumerTasks registers synchronously before task execution. Quiescence
cancels its actual Task and awaits task.result, even if work ignores cancellation.
Completion and rejection each preserve lifecycle validation and cancellation checks.
Finished registrations retire without altering a quiescence snapshot already held.

Cover resolve/generate capture their original writer boundary and validator before
any await. Both explicit async work and lazy backfill can run through a graph's
retained task owner. Internal resolve/generate paths avoid nested registration.
Files and cache writes use the original boundary, never a late mutable global.
Widget publish/index capture their owner, validator and shared boundary; indexing
rechecks before/after OS awaits. Live Activity update/end capture their validator
and are retained/drained by the graph task owner when installed.

DraftStore keeps an immutable per-instance boundary; every write uses it. AppStore
accepts its own DraftStore and AddRecipe uses that retained instance. Old editors
cannot clear a replacement owner's draft by looking up a mutable singleton.

Defaults remain legacy for old callers and isolated tests until the production root
binds them in the final packet. This is not complete activation. Remaining work:
actual root owner installation; full editor/generator/auth/sync task closure and
drains; safe auth/reset/import rebuild with old UI retired; reset inventory/system
surface integration; generation-aware sync; production startup and unified UI.
Shared boundary replacement must use a stable owner-aware router, not test reset.
Signed-in startup stays blocked on missing/unverifiable remote contract. No
assumed generation 0 or offline legacy fallback.

Three new native methods added to exact-head full-unit required list (78 -> 81):
- cancellation-ignoring work is awaited and cannot publish after quiescence;
- closed owner refuses work before body executes;
- original DraftStore cannot mutate replacement draft after original boundary closes.

205 Python pass, 10 Swift grammar parses and diff pass. Native compilation/tests,
OS Activity/Spotlight behavior, cancellation integration and device pixels UNRUN.
Reviewer-hosted native results only. No assertion weakened or timeout/retry added.
