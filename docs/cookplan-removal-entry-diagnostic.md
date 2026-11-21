# CookPlan removal-entry diagnostic, not a fix

## Failing evidence

PR592 source d81646f7e7334a8b7705ae1bd60432ce7413f535, Compile run44917186447 attempt1, build-nutrition job136885308475. Full AteTests selection ran1346 tests with1failure. CookPlanNotificationTests.testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly failed its existing2s utility-entry expectation at native source217,65.323s total. Raw full-unit coordinates719–747 are preserved in build job lines16471–16499. Later tests passed, but final native result remains failed.

- https://github.com/melusi-k/ate-ios/actions/runs/44917186447/job/136885308475
- https://github.com/melusi-k/ate-ios/actions/runs/44917186447/artifacts/14712916359

Exact failing test/helper/project source matches main ffa7fdcf242acdf7005905c3c05a39613cbb3976. The helper enqueues the synchronous removal operation on global utility dispatch, awaits a checked continuation, and resumes only after the operation returns. The test launches this call inside a MainActor task, starts a2s XCTest expectation wait, then checks ordered nonreturn on Main before releasing its semaphore. The callback currently performs two XCTest assertions before fulfilling entry. Without boundary timestamps, a failed entry wait cannot distinguish delayed MainActor task entry, utility dispatch latency, assertion/fulfillment delay, or delayed XCTest waiter return. The65.323s duration alone assigns none of these causes.

Retained historical logs show this same named method passing0.003s,0.014s and0.647s. These are evidence of variability, not a fix or proof the current failure is infrastructure-only. Exact historical run binding is not reconstructed by this diagnostic.

## Scope

Only monotonic phase stamps in this one native test plus its file-private print helper. Test entry, MainActor task entry, utility callback entry before assertions, before/after fulfillment, wait return, release and removal completion get monotonic nanoseconds and main-thread identity. No actor/queue change, delay, timeout increase, retry, skipped assertion, new fixture or app behavior change. All existing native source is byte-identical after removing these exact diagnostic lines/helper; the new Python guard pins that original hash and the entire unchanged app implementation hash.

456 Python tests pass10.273s. Native build/test not run locally. No native correctness, physical-device result or root cause is claimed from source/Python checks.

## First-result interpretation

Use the first ordinary exact-head gate result, never rerun an unchanged candidate to obtain green.

- Late main-task-entry relative to before-entry-wait: test's MainActor task scheduling or occupied main executor is the first observed boundary. Investigate concurrent main work before changing app dispatch.
- Prompt main-task-entry but late utility-callback-entry: the app's utility offload boundary is delayed. Investigate worker scheduling/thread samples; changing the test wait would hide this observation.
- Prompt callback-entry but late before-entry-fulfill: callback assertions/XCTest machinery delays entry signaling, a test-harness boundary.
- Prompt fulfillment but late wait-return: XCTest waiter/executor scheduling is the observed boundary.
- Prompt phases with a first-run pass: diagnostic non-reproduction only, no root cause found and no repair accepted.

Thread samples can further separate ownership. A phase record locates delay; it is not automatically an app regression or a test defect. Reviewer owns normal-gate review and merge. Builder must not merge this PR.
