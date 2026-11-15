# Ordinary generation ownership (#35 / #89)

Incremental base:88179b2e80d37b6255efee296867a470473fa93b (reviewed quality tail).
This is not a replacement of #517 or permission to restart it. Transport must
retain its Journal header additions and #518 Cook changes independently.

## Source finding

Ordinary AddRecipeSheet generation used unretained Tasks. Unlike explicit repair,
Discard and onDisappear did not invalidate generation. A backend ignoring
cancellation could assign a draft and save DraftStore after explicit clear, or
publish an error/preview/finish into a no-longer-current sheet. Spread secondary
cards had a separate unowned loop writing Library after backend await.
This was found by source inspection, not a new physical reproduction.

## Bounded change

DraftGenerationAttempt owns primary and child tasks and an admission token.
Duplicate concurrent primary start refuses. Discard invalidates before clearing
DraftStore; disappearance invalidates without deleting recoverable pending input.
Invalidation cancels all owned tasks AND closes admission. Every result/error,
preview, deferred UI cleanup and spread post-await write checks the token. A new
attempt replaces admission; old completion cannot clear its loading/task owner.
Request mode/link provenance is captured before await. Children may finish while
the primary review card is open; next generation/discard/disappearance revokes them.
Spread saved-count copy now counts actual successful results, not attempted ones.

Four native helper fixtures cover delayed cancel-ignoring backend discard,
non-discard pending input retention, duplicate/new-attempt ownership and late
spread Library refusal. All four names are added to full-unit-required.txt;
no existing named check/selector/assertion/timeout is removed or relaxed.
The Python routing snapshot is extended with the exact four required names,
retaining its original ordered25 and exact-equality check. The first Python run
after adding the names failed that old25-only snapshot as expected; it is not
reported as a pass.

## Limits

Native/Swift/model/UI/device/pixels NOT RUN. Python185 PASS and diffcheck are
source checks, not these native passes. Existing interrupted-generation and
retry UI journeys still require exact-head results. No layout intended to change.
No claim of every #35/#89 acceptance clause, arbitrary model reliability, OS force
quit behavior, source extraction coverage, or physical lifecycle certification.

This is per-sheet ownership. It does not replace the backend's process-global
partialSink with a per-request stream API. Spread preview cross-talk while both
requests are valid is still possible and not solved by this lifetime gate.
Cover-generation/photo-picker tasks are separate and unchanged. Existing earlier
spread cards saved before discard are not rolled back. No production Food
Journal activation, sync behavior or notification permission change.
