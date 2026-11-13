# #517 exact-head assertion and cleanup follow-up

Base: #517 head7ee50cada9f61832385dfa2cc335dfbebc2f8658. Reported native
run43302044080: PhotoRegressionTests.testTotalTimeComesFromStepsPlusPrep got7,
expected12; Lane3WriterBoundaryTests.testCleanupRemovesEveryVerifiableSnapshot
exceeded4minutes. No prior result is erased or reclassified as passing here.

## Time assertion (product source contract)

The generated-total change routes photoGuess into absent-prep step-sum7, bypassing
the retained legacy photo cap12. The later time-normalization tail has the SAME
branch and does not fix this. Preserve both existing contracts: only legacy
photoGuess without ANY Prep declaration uses the previous bounded total path.
Apple Intelligence absent-prep still means step sum with no invented prep.
Explicit photo Prep uses strict shared parsing/total arithmetic, including
malformed Prep refusal. No existing expectation or timeout changed. The remaining
5minute legacy gap remains visible to consistency validation, not fabricated as
an authoritative Prep note. Additive fixture asserts12, idempotence, missing note,
visible explanation gap, explicit12prep=>19 and malformed prep preserved.

## Cleanup already fixed on current main, absent from branch

#514 mergee6bcae0 includes callback-based Spotlight deadline/cancellation and
single-resolution completion gate. #517 still has unbounded async deleteAll.
This packet restores exact main source/test/doc bytes for those4paths rather than
invent a second timeout policy. Default production5second deadline reports the
Spotlight surface UNVERIFIED, permits other snapshot/log cleanup, and never claims
OS deletion succeeded. No XCTest allowance increase, test skip or mocked snapshot
assertion. The4minute report is consistent with the known unreturned Spotlight
path; without the exact stalled stage, causal attribution remains unverified.
Other awaited system boundaries are unchanged and not declared exonerated.

## Validation

Python/static checks only, not new native execution. Reviewer must fold with
in-flight tails, compile Swift and rerun normal exact-head qualification under
existing rules. All existing photo and generated-time expectations stay intact.
Food Journal activationOFF; no merge/push/dispatch by Builder. #522 depends on
accepted root#517 and still needs its own final-head proof.
