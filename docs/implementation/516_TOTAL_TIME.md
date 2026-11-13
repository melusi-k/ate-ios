# #516 generated total-time reconciliation

Incremental on lifecycle-fixed explicit-repair14de3fa (and source-fidelityv2a9ff476 beneath it).
Branch-only; no native/model/device pass, publication or activation.

Diagnosis: Durations.sanitize corrects written step time first, then applies a
legacy total cap of `stepMin + max(5, ingredientCount * 2)` while ignoring the
card's explicit `Prep: N min`. GeneratedRecipeConsistency separately requires
the stated prep sum. Thus normalization can create/preserve exactly the mismatch
its validator then flags. The four supplied build438 examples are regressions.

Fix: share one explicit-prep parser and, only for generated cards with known step
sum, write total as rounded total step seconds plus stated prep (or no extra prep
when none is stated). Do not apply the unrelated ingredient-count prep cap to an
explicit generated prep note. Keep non-generated manual/imported behavior as-is.
Reject implausible prep sum by leaving its disagreement visible rather than
silently guessing a replacement. No change to written step durations or ingredients.

Ten native fixtures cover the four exact device arithmetic examples, written-
time correction, normalization idempotence, no prep, cap regression, rounding once
across short steps, unchanged non-generated behavior and explicit-prep parsing.
Python185PASS/diffcheckPASS only. Swift/native and device/model NOT RUN; existing
native assertions untouched. Exact-head native qualification must check interactions
with quality-repair scoring, which now compares normalized cards.

This does not certify model timings, food safety or elapsed-vs-overlapping step
schedules. It makes the product's existing stated step-sum contract internally
consistent. Ambiguous prep text/ranges fail closed with a clarification gap rather than
being silently dropped; the total remains unverified. Source imports must not invent prep;
#509 source fidelity remains separate. Source https://github.com/melusi-k/ate-ios/issues/516 .

Parser review follow-up: count all Prep declarations (including whitespace before
colon) before reading the sole value. Whole-value boundary rejects ranges, decimals,
composite values, mixed valid/malformed duplicates and no-space suffixes. Native
regressions include both reported duplicates and `Prep:10min plus30seconds`.

Bounds follow-up: prep parser accepts only 0...Durations.maxTotalMinutes; a shared
total helper checks both operands and remaining allowance before addition. The
validator also bounds accumulated step seconds before addition. Int.max, near-max,
text beyond Int, supported-limit overflow and exact-limit cases are native fixtures.
No claim of Swift execution. Excessive prep stays a named clarification gap.
