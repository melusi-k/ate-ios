---
name: ate-code-review
description: Use when reviewing Ate pull requests or working code for SwiftUI structure, accessibility, concurrency, testing, and performance problems that style checks and compile checks do not catch.
---

# Ate code review checklist

## Goal

Catch the recurring classes of bug that pass compile and CI but degrade the app: unstable view identity, forced unwrapping patterns, isolation mistakes, missed accessibility, and performance regressions.

This skill supplements, and never overrides, the root `AGENTS.md` and the domain skills. Testing specifics live in `ate-testing`; SwiftUI and navigation specifics live in `ate-swiftui`. When guidance here conflicts with verified code, inspect the implementation and update the documentation through review.

Adapted from MIT-licensed agent skills; copyright and permission notices are retained in `THIRD_PARTY_NOTICES.md` at the repository root.

Detailed checklists live in:

- `references/swiftui-review.md` - SwiftUI structure, modern API, and accessibility gates.
- `references/concurrency-review.md` - Swift concurrency hotspots.
- `references/performance-review.md` - performance smell triage, profiling evidence, and report templates.

## When to use

Use for any substantive PR review, and when a change touches view hierarchies, shared state, async work, or list rendering. Read the relevant reference file before applying its gates.

## SwiftUI review gates

- No deprecated-or-superseded API in new code: `foregroundStyle()`, not `foregroundColor()`; `clipShape(.rect(cornerRadius:))`, not `cornerRadius()`; `NavigationStack` with `navigationDestination(for:)`, not `NavigationView`; `.scrollIndicators(.hidden)` rather than `showsIndicators: false`.
- Never the one-parameter `onChange(of:)` variant; use the two-parameter or zero-parameter form.
- `Text` uses interpolation (`Text("...\(value)...")`), never string concatenation.
- When touching `TabView`-based chrome, prefer the `Tab` API (available on the iOS 18 deployment target) over `tabItem()`.
- `@State` is always `private` and initialized in exactly one place.
- In `ForEach`/`List`, identity comes from the element's stable id, never from indices, offsets, or `id: \.self` on mutable collections.
- Button actions and business logic live in methods or model types, not inline in `body`, `task()`, or `onAppear()`.

## Accessibility review gates

- Dynamic Type everywhere; no forced font sizes.
- Use `Button`, not `onTapGesture()`, unless tap location or count is genuinely needed.
- Image-labelled controls keep a text label (`.labelStyle(.iconOnly)` when icon-only) so VoiceOver has something to read.
- Interactive targets stay at least 44x44 points.

## Concurrency review gates

- `Task {}` inside loops is a smell: for owned child work that shares a lifetime, prefer `withTaskGroup`/`withThrowingTaskGroup`. Intentional long-lived owned tasks with their own lifecycle are legitimate.
- `Task.detached` is suspect; justify shedding isolation and priority or do not use it.
- Every `withCheckedContinuation`/`withCheckedThrowingContinuation` resumes exactly once on every path.
- Never add `@unchecked Sendable` to silence the compiler; fix the isolation.
- `catch` blocks filter out `CancellationError` before handling other errors.
- Cancel owned tasks before replacing them, and on their owner's teardown, respecting the existing owner.
- Audit check-then-act sequences that cross an `await`: revalidate invariants after the suspension and preserve cancellation, generation, and identity checks. Not every such sequence is a bug; see `references/concurrency-review.md`.
- No `Task` created inside `onAppear()`; use the `.task()` modifier.
- Handle errors inside throwing `Task` closures; a silently dropped error looks like nothing happened.

## Testing review gates

- Repo convention is XCTest; see `ate-testing`. Do not migrate tests to Swift Testing or add testing frameworks without owner direction.
- Never weaken assertions, add mocks to make a failing test pass, skip failing tests, or raise timeouts to hide an unexplained failure.
- No timing-based tests: never sleep to "wait for something to happen". Await the real async work or bridge callbacks with a continuation.

## Performance review gates

Review in triage order: broad invalidation, unstable identity, main-thread render work, image cost, layout/animation complexity. Flag the smells in `references/performance-review.md`; do not accept `equatable()` or `@State` caching as blanket fixes.

## Verification evidence

A review verdict states what was inspected (files, gates applied), what passed, what was not inspected, and any hypothesis that profiling or testing has not yet confirmed. See the report templates in `references/performance-review.md`.
