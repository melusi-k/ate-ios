# #195 first slice: latest-request Health refresh ownership

Branch-only base6f9fe56fc3fc3a8a544d79450006592a6316b375. No publish/merge,
new provider, network, analytics or Food Journal activation. No new UI layout.

Observed gap: local recipe candidates have a generation fence, while Health
summary and optional on-device prompt generation awaited without ownership checks.
Older completion could replace fresh context and publish stale shared/widget state.

InsightsModel now captures a unique refresh token and concrete source, checks token,
cancellation and current source access after BOTH awaits. Only the current request
may end its loading state. Context and widget state publish synchronously together
only after summary+wording remain current. Scenario/authorization transitions first
invalidate prior refresh, clear context and reject stale authorization completion.
Prompt and widget publication seams are injected for deterministic no-side-effect
tests; default implementation still uses existing prompt/WidgetBridge behavior.

Four required native tests ADDED, prior required list unchanged: late old summary;
late old prompt plus loading ownership; access loss/cancellation at summary; access
loss during wording and empty evidence. Fixtures use continuations, no sleeps,
timeout/retry increases, real HealthKit, model, defaults or widget side effects.
207 Python PASS and diff-check PASS; Swift grammar clean only.

Native build/XCTest and warnings UNVERIFIED: no Xcode here. No screen layout changed;
existing presentation/UI suites still required for acceptance. Scope does not claim
complete cross-domain orchestration, shopping/diary seeded destinations, versioned
language semantic validation, usefulness analytics or physical-device qualification.
Explicit-dismiss retention/lifecycle semantics are untouched. Source issue:
https://github.com/melusi-k/ate-ios/issues/195
