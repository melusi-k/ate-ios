# Python script suite: one candidate-head Linux job

This delta runs the complete existing `scripts/tests/test_*.py` suite once in Compile's new `python-tests` job on Ubuntu, with explicit PR head checkout (or the event SHA for WIP/manual events), read-only content permission and checkout credentials disabled. No tests or failure assertions are removed. It also runs for documentation-only diffs.

Removed duplicates: Compile's build-nutrition job, both regression matrix workers, its mutually exclusive docs-validation route, and Dogfood's Python discovery step. The candidate job is required by the existing `compile` aggregate and `Compile qualification result` gate. Those names, native lane predicates and strict failure handling remain. Failed, skipped or cancelled Python results cannot pass the existing final gate.

Dogfood's separate Python execution on the synthetic PR merge ref is intentionally removed. This is an explicit coverage-context decision, not a claim that merge ref and head are identical. Dogfood's native checkout, full unit selection, critical flows, quarantined diagnostics and final qualification gate are unchanged in this delta. In particular, SyncAccount remains non-qualifying. Native unit-lane consolidation is a later reviewed delta.

There is no automatic main-push invocation of the complete Python suite in the current workflow set. Build IPA runs check-ids, not Python unittest discovery. This delta adds no post-merge workflow or trigger and makes no post-merge script-suite claim. Trusted-main and tokenless candidate stack-validator tests remain separate because their trust contexts differ.

This reduces repeated Python work on Mac workers. It does not remove their separate builds or native tests, promise measured runtime savings, or add paid capacity. Mac jobs remain parallel and the existing native budgets are unchanged. Linux portability has been checked offline against the complete suite, not demonstrated on a hosted run yet.
