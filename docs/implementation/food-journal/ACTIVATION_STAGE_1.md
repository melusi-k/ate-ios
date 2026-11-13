# Food Journal activation, stage 1: admitted retained graph

Part of #245. Base a6a3146947213b540f969d375de407d0efebcdd0, built on the
273fb31a4fe5e203d996201932b2322d160d48a0 integration branch. Reviewer publishes.
This is implementation of the graph seam, not completed production activation.

## Implemented

FoodJournalAppGraph.startup retains AccountResetComposition, original writer lease,
one reentrant FoodJournalWriterBoundary, FoodJournalRuntime and AppStore. It uses
existing reset resume and asynchronous admission before personal resource creation.
The original lease is revalidated after awaits. Resource construction and AppStore
load share one account-outer/archive-inner covered unit. No fresh lease substitutes
for a stale one. All archive callbacks and preservation directory are required by
this graph, and are installed in AppStore before load rather than after root mount.

AppStore now gives TimerCenter the same runtime boundary during construction.
Previously TimerCenter stayed on its legacy boundary even with a canonical runtime;
setting it after construction also leaves constructor-side QA writes unbound.
Existing default callers retain their prior behavior. This is a source-supported
composition fix, unrelated to the unproven #518 SwiftData timer crash.

Three new native tests cover blocked snapshot/no constructors, ready capability and
original-lease ownership with one generation unit, and admitted cook retry retaining
session/title/day/outbox without meals or automatic reflections. The cook regression
also invalidates the epoch and verifies that old acknowledgement/session-clear work
cannot mutate retained state. No existing test or timeout was removed or changed.

## Remaining production stages

- Provision immutable app-group control/lock paths without standard-default fallback.
- Bind real archive recovery/capture/import, reset inventories and surface cleanup.
- Verify deployed signed-in snapshot/generation contract before production root mount.
- Ensure auth rotation, sync, extensions and deferred surface work use the retained
  epoch. Stage 1 alone does not certify these independent participants.
- Audit defaults domains: AppStore settings/meta still use standard defaults while
  runtime cook/goals use injected domains. Real production resource choices must
  match actual owners; an arbitrary isolated Resources fixture is not production proof.
- Mount preparing/ready/recovery root in AteApp and remove eager legacy constructors
  only after all capabilities exist. No invisible fallback after canonical writes.

## Rollback before any merge

Stage 1 does not change AteApp routing or disk formats. Revert the stage commit to
restore the previous constructor API and TimerCenter default binding behavior.
Once canonical routing is enabled in a later stage, rollback means keep the same
canonical stores and recovery controls with read-only/recovery admission if needed.
Never delete canonical bytes, reset receipts, restore legacy keys or remigrate into
an empty graph to make an older route appear to work. Branches remain retained.

## Evidence

155 existing Python infrastructure tests PASS on this source; git diff --check PASS.
New native XCTest tests are written but UNRUN. No Xcode, SwiftData runtime, native
build, Darwin/two-process lock proof, actual archive/reset roundtrip, UI pixels or
physical-device evidence available here. No production route, merge, deployment,
account mutation or live data reset was performed. Reviewer must qualify exact head.
