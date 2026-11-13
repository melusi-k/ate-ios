# Packet 2: explicit quality repair, not dish re-ask

Incremental on source-fidelity v2a9ff476. Branch-only, no publication or native /
model/device acceptance. #253 F10's device path asked the dish again; it did not
prove repair of the retained failed draft. #507's missing bread was correctly
flagged but still not fixed in model output.

## Changes

- Review's quality panel offers `Repair these gaps`, separate from Regenerate,
  the transport Retry button, the dish-name question and an asked rewrite.
- Optional ParseRequest repairQuality flag uses the existing rewrite transport
  with the exact current card JSON and its actual named shortfalls. It does not
  replace the card with a dish-only prompt. Same surviving model session is used
  through reviseID; JSON always accompanies the repair if the session was evicted.
- No automatic second repair after this explicit one. No permanent auto-loop.
- Acceptance requires same dish and servings, strictly fewer existing gaps and
  no new gap, after normalization. Preserves stable id, createdAt, favorite, sort,
  cook date, media, source/origin and original confidence/alternatives. A lower
  count with a new missing food is not an improvement. Failure retains the draft
  and exposes the error, save is disabled while repair is in flight.
- The initial automatic repair comparison now also uses normalized strict-subset
  gap comparison plus stable dish/servings, rather than count alone. It still
  runs once. Source-fidelity validation remains required for recognized captions.
- No deterministic guessed bread quantity is inserted in production. The model
  must supply measured bread and still pass checks; otherwise the card stays a
  draft. #507 remains open until actual F12 regeneration and repair succeed.

## Qualification

Six new native repair-policy fixtures plus one synthetic UI journey exercise
missing measured bread, unrelated reroll/new failure refusal, exact-draft prompt,
identity/confidence preservation, generated/gap eligibility and automatic repair
selection. A UITesting-only `-qaDraftQualityRepair` fixture serves the synthetic
missing-bread card and repair to exercise real review-button wiring. Demo mode
otherwise refuses this new repair rather than claiming success. This fixture
is not a recipe or model-quality pass and is unreachable outside UITesting.

The existing transient-retry Compile step includes the additional UI class and
requires its exact named pass; its original test and assertions remain. Screenshots
are keepAlways and exported after that step on any outcome. Reviewer transports
this addition alongside early artifact retention; the existing transient step's
result path remains unchanged. No runner/job/test allowance increased.

Python185PASS, YAML parse and35shell blocks syntaxPASS, diffcheckPASS. Swift6/native
compile, those seven native/UI methods, actual review pixels and model F10/F12
outputs: NOT RUN. Visual verification is required before the new control is ready
for device acceptance. Error text/scroll/landscape and post-relaunch original-source
availability remain unverified. The source-fidelity contract only covers its named
inline-caption shape; this does not silently qualify all imported source repairs.

Sources: https://github.com/melusi-k/ate-ios/issues/253 and
https://github.com/melusi-k/ate-ios/issues/507 . No issue closure or activation.

## Lifecycle follow-up

The repair action now owns its Task and an admission token. Discard and disappear
invalidate the token before clearing/dismissing; cancellation alone is not trusted.
The synchronous MainActor apply closure runs only after the post-await token and
cancellation check, and rechecks captured-draft equality before any DraftStore
write. A delayed backend fixture deliberately ignores cancellation, then returns
after invalidate+clear and proves no persistent draft resurrection. A current
admitted attempt still applies/finishes. Native tests and pixels remain NOT RUN.
