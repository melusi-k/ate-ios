# Slice 16: isolated standalone local collaborators

Dormant, Food Journal stays OFF. RecipeShoppingLocalServices constructs explicit
draft/timer/history/cook outbox/offer and injected Journal consumers without making
FoodJournalRuntime or running diary migration/archive/meal startup.

Admitted construction uses actual resources owner and owner-produced shared-ready
boundary, exact authority defaults and explicit shared defaults. Requires existing
strict Journal container/state via supplied factory. No JournalStore.shared open.
The service validates original owner/defaults/boundary before AppStore accepts it.

Authority AppStore without a valid supplied local-services binding receives private
REFUSING collaborators, not DraftStore.shared/TimerCenter legacy or cooking-history/
Journal singletons. No QA launch reset runs for authority construction. External
current/relays/widgets require valid local-services binding as well as raw inventory
proof. Cook identity remains separately gated after full inventory validation.

CookingHistory's additive writer boundary covers record, verified-record and clear
before memory/defaults changes, legacy default unchanged. TimerCenter's additive
explicit snapshot defaults and resetForUITesting flag avoid global shared-domain
fallback and launch clearing in standalone; default existing callers unchanged.
AppStore local cooking/history/outbox/Journal accesses route to standalone services.

Two native tests UNRUN: refusing collaborators preserve seeded draft/history/timer
bytes; admitted real gate/resources collaborators use exact defaults and cannot
clear/recreate bytes after old owner epoch retirement.207 Python PASS.

Open: singleton CoverStore/PhoneWatchBridge/LiveActivities producer binding and
retirement; final Journal strict-open factory; auth host mount/unmount and all shared
boundary installation; account actions/export/import must not take old legacy paths.
This does not claim production-safe complete graph or automatic activation.

Follow-up: shared readiness helper and later local-services construction now rotate
the durable owner epoch on failure, including failure after publishing readiness.
Readiness construction refuses nested entry from an already-held owner effect, so
cleanup runs after its flock unwinds. A native fixture captures an extension during
Journal-factory failure, then proves both captured and newly created extension
boundaries refuse. No swallowed rotation failure or stale-marker success claim.
