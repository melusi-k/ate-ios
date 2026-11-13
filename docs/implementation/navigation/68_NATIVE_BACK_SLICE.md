# #68 first slice: focused native header/back coverage

Source: https://github.com/melusi-k/ate-ios/issues/68
Base:6f9fe56fc3fc3a8a544d79450006592a6316b375, branch-only.

The shared root chrome and RouteView inline treatment already exist. This slice
adds coverage for an explicitly unproven path, without speculative layout edits:
Journal tab root -> Insights & Cooking History -> native Journal Back -> repush
-> interactive leading-edge swipe -> original Journal content. Strict assertions
require one header, root-only logo, native labelled/hittable Back, restored content
and selected Journal tab. Four retained normal-text portrait captures. No custom
Back button, fallback tap, gesture override, retry, timeout increase or removed
assertion. Existing CookingTrackerEntryUITests class is already selected by the
account-cooking regression job; no new job or workflow dispatch.

Native test:
CookingTrackerEntryUITests/testJournalAndInsightsHeadersPreserveNativeBackAndEdgeSwipeAtNormalText

Python207PASS; Swift grammar/diff-checkPASS. No production code changes.
Native compile/typecheck/warnings/XCTest and visual pixels UNVERIFIED. No simulator
or Xcode is available here. Exact-head native run and screenshot inspection must
confirm transitions and root chrome restoration. This is a test packet, not proof
of behaviour or visual readiness. It changes no issue checkbox, acceptance gate,
Food Journal switch or user data. All wider root/push/orientation/keyboard/sheet/
VoiceOver and device checks remain open. Normal text only, larger Dynamic Type
is not silently qualified. No publish, merge, PR, issue closure or CI dispatch.
