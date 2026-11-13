# #496 diagnostic-only retention

Exact base7813a42f5b1aa638ee2bd5233e2f0390ce86b2f1. The retained focused log
contains only tail120 after xcodebuild failure. Final failing-tests list names
ExploreUITests.testExploreDismissPreservesCollectionAndSearchQuery, but its start,
step/error/assertion/timeout are absent. A later selected suite shows3passes,
including saved preview/detail and landscape Done. Overall xcodebuild is failed,
not a pass. Earlier nonexistent legacy Back helper was fixed by #503; later
preview/detail pass supports that repair, not a guess about this failing method.
No earlier same-source full log exists per Reviewer, and artifact upload failed
ENOTFOUND. Failure cause UNCLASSIFIED, not declared product/test/stall. No retry.

This change touches ONLY diagnostic workflow retention, extractor, static fixtures
and these notes. Runtime, Explore test source, assertion set, named required passes,
selectors, waits, timeouts, runners and job budgets remain byte-identical.

After the existing focused step, an always step copies COMPLETE Explore log to
an independent directory and emits it in console (both readable and lossless
base64 chunks with byte count/SHA256). It extracts xcresult summary/tests JSON,
retains extractor stderr/exitcodes and exports all attachments. Missing bundle
is explicitly missing evidence, not no failures. Summary/tests JSON and exported
PNG/JPEG/JSON/text attachments also mirror into console so a later bulky artifact
DNS/upload failure doesn't remove the ONLY route to failed-method/screenshots.
Complete export stays in the small independent artifact, before later suites and
before the existing bulky diagnostics upload.7day retention, existing v7 upload
action family, no new job/paid runner or extra test execution. No assertion waiver
or continue-on-error added. Extractor errors do not erase original failed step;
they are visible in diagnostic files/console. Unexpected extractor exceptions
still fail retention. Existing full diagnostic artifact remains unchanged.

Console fallback is best-effort under GitHub log size/retention limits; no upload
can guarantee delivery during service outage or hard runner cancellation. Text
is streamed first and screenshot chunks later. SHA256/bytes allow recovery
verification; reviewers must inspect decoded pixels, not claim the fallback
script proves screenshot quality. Only synthetic Explore UI fixtures run here,
no new personal-data collection/source retrieval. Native extraction on Xcode27,
network outage and next exact-head Explore execution NOT RUN. Python mocks test
missing bundle, failed extractor, PNG mirroring and full earliest-line retention.
Actual next failing-method detail still required to classify root cause.

Reviewer publishes branch-only incremental packet onto #496, Explore remains ON.
No modified tests or reruns requested by Builder. #523 stays OFF and last.
