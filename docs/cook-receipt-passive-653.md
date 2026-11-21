# Passive named-red inspection

Base: PR653 f6fa894e67f0e5acfb163ea633a0b15317d57738.

First run44927949487 stays RED for its UI timeouts. CookPlan diagnostic is a non-reproduction,1346/0 full-unit, not a fix. No previous red is reclassified.

Completion diagnostic inspection performed extra remote exists/frame/identifier/label reads. Its monotonic body took29.738s, its enclosing xcresult activity30.028s. Screenshots before the allowance boundary total3.787s. Bottom-bars nominal5s timer wait took49.641s; offline-banner existence queries also took30s. At the late timeout boundary, its spindump shows the runner waiting for remote snapshots and the app main thread in injected XCTest query traversal, with290/359 sampled stacks containing logging mirrored to stderr. This does not prove every earlier stall has that cause.

Change: diagnostic inspect emits passive BEGIN/ELEMENT/END stamps. Its ignored XCUIElement argument preserves existing call sites without reading any remote property. Optional plain String capturedValues permits logging values a caller already holds; current callers provide none. Output explicitly says phase-only, not exists=true or a fabricated frame. Screenshots, journeys, all behavioral assertions, waits, selection,180s allowance, app code and workflow remain unchanged.

Logging investigation: checked project.yml, UI launch helpers and workflow. No repository-set OS_ACTIVITY/OS_LOG/IDEPreferLogStreaming switch was found. NSUnbufferedIO appears only in Nutrition and ingredient progress-stream commands, not these Cook commands. The Cook commands write xcodebuild stdout/stderr to regular retained log files. No unsupported global logging suppression is added. The sample demonstrates logging I/O waits inside injected AX work, not proof of an application timer bug or the underlying I/O resource. This passive fix reduces avoidable query demand; it does not claim to fix the original bottom-bars assertions' AX latency or Explore's longstanding two60s animation-idleness waits.

Validation: Python source/regression suite458 tests pass. Source pins require exact journey/assertion files, CookPlan tests, workflow and project. Existing historical inverse pins are unchanged. Native compilation/UI qualification requires the new exact head; none claimed locally. No retry, merge, cap increase, assertion removal, timer logic or Cook logic change.

Evidence: https://github.com/melusi-k/ate-ios/actions/runs/44927949487/artifacts/14721140981
