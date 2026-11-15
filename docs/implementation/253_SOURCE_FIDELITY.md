# Generation quality packet 1: pasted-source guardrails

Branch candidate only, main527dfb6 base. Reviewer transports into an existing bundle
within the six-PR cap; no publication, native pass or device/model improvement claim.

## Diagnosis

#511 F2's no-dish advert was refused on the fetched-social path only. Pasting that
same caption in Prompt entered the creative prompt mode and skipped the early
refusal entirely. Model output then supplied its own invented disambiguation name.
The candidate applies the existing grounded-promo check before Prompt fallback,
streaming and generation; OCR text is checked after OCR before photo generation.
A named-dish menu and normal dish request remain eligible. This heuristic is not
a general dish recognizer; unknown legitimate dish names in ads can still need
manual clarification. No new list of guessed regional names is introduced.

#510 F1 explicitly supplied quantities/method but entered Prompt's creative path.
The shared Chakalaka example has different quantities and15-minute simmer; the
observed output resembled that example. That is a plausible influence, not a
proven model trace. The candidate recognizes a narrow explicit `You need ... .`
measured inline list, routes it through the existing social extraction brief,
retains a source contract, adds its fidelity gaps to the single repair attempt
and rejects a still-divergent final normalized card. No source item is fabricated
to satisfy a validator. Its streamed preview is suppressed until acceptance,
so an altered card is not shown as95%-confidence while still being checked.
Model-unavailable recognized extraction refuses instead of substituting Demo.

The contract compares source names/order, quantities/units, extra/duplicate items
and explicit cooking-time sequence. It permits bounded prep-word separation and
singular/plural forms, not guessed food aliases. It does not prove full semantic
word-for-word extraction, arbitrary lists, OCR structure or prep-note fidelity.
Unsupported input is NOT silently labelled verified. #509 remains separate.

## Limits and remaining work

- #510 remains PARTIAL until real F1 output preserves the source after repair.
  Refusal prevents accepting corrupt extraction, but is not successful import.
- #511 image fallback when the model is unavailable is unchanged; fetched-social
  refusal already exists. The added actual-backend fixtures cover pasted Prompt
  with model available/unavailable. Full path/device acceptance remains open.
- #507 generator missing ingredient and #253 F10 retry-repair are next, then #516,
  #509, #513 and #515. This packet does not claim them fixed.
- Existing source prompt snapshots/size constraints remain unchanged. No prompt
  examples dropped, model provider change, cloud call or paid capacity added.
- Native fixtures cover exact F1 measured values, observed corruptions, duplicates,
  ingredient order, written times, bounded prep normalization, unsupported formats,
  F2 full/shortened advert refusal and actual pre-model/fallback behavior.
- Python185PASS and diffcheck PASS. Ten new Swift fixtures, Xcode, model streaming,
  repair behavior and real F1/F2 rerun: NOT RUN. Existing tests/assertions unchanged.
- No UI pixels changed or inspected; future error/stream behavior requires device
  verification, including that refusal leaves the user's input available to edit.

Sources: https://github.com/melusi-k/ate-ios/issues/510 and
https://github.com/melusi-k/ate-ios/issues/511 . Source truth is current main
OnDeviceBackend (live-checked equal to527dfb6), RecipePrompt and existing F1/F2
fixtures; observed model output is evidence, not an instruction or an authority.

## Review correction

Reviewer found the first packet reduced written duration ranges to their upper
bound. That could incorrectly certify a lower-bound change or removed range.
The revised contract compares ordered `Durations.Span(lower, upper)` values using
the existing duration parser. Added fixtures cover hyphen/en-dash/to ranges,
changed lower/upper bounds, removed ranges, composite hours/minutes, equivalent
units and reordered spans. No passing device or native result is inferred.
