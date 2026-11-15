# Food Journal linear native qualification candidate

Base: main1015437a62fb7bf95b5222a29a7e9daae807bf94. One linear branch, no merge
commits. Production `foodJournalEnabled` stays false. No backend deployment,
production personal-data write, anonymous sign-in or workflow-stream activation.
Food Journal remains local-only; recipe/shopping use the generation-aware transport.

## Source provenance

The dormant factory delta through79636cf3 is consolidated as one foundation
commit on main. Its tree exactly matches79636cf3 before replay. All prerequisite
commits then replay in order without product edits/conflicts:

- c70e5b1c: retained consumer tasks and drains
- 1a3d3230, ca46b7df,83d6209f: graph transitions, PT409 client/SQL dependency,
  retired-owner failure drains (prerequisite2v2)
- 6677ad1e: raw reset inventory and captured shared owner
- c787d7aa,46466cf5,a3715411: real application root, extension/shared notification
  ordering, strict watch account/cache/current-snapshot shopping actions

Before OFF qualification changes, the replayed tree exactly matchesa3715411.
All34 main native required names are present in the107-name final manifest.
Native routing guards preserve the original named ledger and every added method.
No test timeout, retry, mock, skip or CI budget change is part of consolidation.

## Native proof required on the exact qualification head

- Compile every affected iOS application/widget/share target and watchOS app/widget
  target, including shared code. Grammar parsing is not compilation/typechecking.
- Compile/build-nutrition full exact-head AteTests lane must execute, have no
  failures and retain every one of107 required method names. This includes owner,
  generation/receipt, strict disk recovery, archive import/export, consumer drain,
  real image-provider completion, ordered notifications and watch ownership tests.
- Run `python3 scripts/native/test-food-journal-process-gate.py` on macOS. Actual
  separate processes must refuse old personal image writes during the reset flock
  and after release/epoch rotation. The script is not a passing test by existing.
- Real production-owner startup with signed-out/signed-in, expired session, valid
  and corrupt keychain/control, app-only and App Group modes. Ordinary personal
  opens must follow pending cleanup and exact snapshot/receipt admission. Do not
  substitute the existing `-UITesting` hermetic root for this path.
- Exercise complete-root removal, active editors, cancellation-ignoring work,
  sign-in/sign-out/account switch, import and reset while operations are pending.
  Verify quiescence, original-owner fencing and no late writes/publications.
- Exercise account-wide reset and startup/crash resume with real temporary/private
  test accounts/data only under separate authorized test setup. Verify personal
  stores, media, goals, drafts, queues, backups, recovery/archive before-images and
  system surfaces, while preserving minimal nonpersonal control. No production
  Supabase mutations are authorized by this candidate.
- Widget/share/intent-only launches must use the same control paths; reset/control/
  stale-epoch/unresolved-archive refusal and delayed image bytes must be observed.
- Await/drain OS notifications and verify no resurrection after cleanup without
  changing the300ms settle. Paused or killed extension submission must remain
  honestly blocked, never expire by assumption. Qualify its recovery limit.
- Watch ownerA->B, failed/offlineB refresh, restart, token changes, ownerless cache,
  retained shopping closures and identical replacement snapshots. No A data or
  item may be shown or sent asB. Phone reset cannot prove offline watch erasure;
  paired-device convergence and that limitation need native acceptance.
- Production Journal root, real unified reflection/save/read-only/repair states,
  archive refusal for linked records, health/cover bindings, timer/cooking finish,
  account settings and normal-text iPhone18Pro navigation need screenshots and
  exact-head evidence. A cook is not an eaten meal. No guessed visual acceptance.
- Existing Compile/Dogfood/Journal lanes remain required on exact head; current
  hermetic green subsets do not qualify the new owner. Native lane failures must
  be classified from logs and artifacts before any code change.

## Deliberate limits

Link-aware archive format is follow-up; linked/corrupt associations refuse, never
silently drop links. A killed extension's unresolved notification submission token
blocks reset/auth until a separately verified recovery route is established. Watch
remote/offline personal bytes cannot be synchronously verified from the phone.
The qualification branch does not claim these limits resolved or user acceptance.

Do not close source PRs until their destination commit is confirmed. Keep source
branches. This candidate is part of245, not issue completion or launch approval.


## Explicit DEBUG production-owner selection

The separately labelled selector commit adds `-qaFoodJournalProductionOwner` only
inside `#if DEBUG`. Launch a Debug app with that argument and WITHOUT `-UITesting`.
AteApp then returns before ordinary constructors and mounts the real
FoodJournalApplicationRoot, with its actual disk/admission/reset/service boundaries.
This does not turn on fixtures, use an in-memory store or fabricate cloud proofs.
Combining the argument with `-UITesting` is refused as owner qualification: the
hermetic path remains hermetic and must not be presented as owner evidence.
Release compiles out the launch-argument selector and the shipping flag is false.
Native selector tests verify ordinaryOFF, DEBUG opt-in and hermetic exclusion;
Release build inspection/typecheck and real-owner UI journeys remain required.
Use an isolated simulator/container and authorized test account for any mutating
journey. This selector grants no permission for production data or backend writes.
