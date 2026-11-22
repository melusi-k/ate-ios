# Concurrency review checklist

Detailed gates behind the concurrency section of `../SKILL.md`. Adapted from [twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) (MIT).

## Task creation

- `Task {}` inside loops is a smell: for owned child work that shares a lifetime, prefer `withTaskGroup`/`withThrowingTaskGroup`. Intentional long-lived owned tasks with their own lifecycle are legitimate; task groups cannot replace them.
- `Task.detached` sheds isolation and priority: require a justification, or rewrite with isolation preserved.
- Never create a `Task` inside `onAppear()`; use `.task()`, which cancels when the view disappears.
- Handle errors inside throwing `Task` closures; a dropped error is a silent no-op.
- Cancel owned tasks before replacing them, and on their owner's teardown, respecting the existing owner. Do not add blanket cancels to tasks another component owns.

## Continuations

- Every `withCheckedContinuation`/`withCheckedThrowingContinuation` resumes exactly once on every code path. Audit early returns, error paths, and delegate callbacks that can fire twice.

## Isolation

- Never add `@unchecked Sendable` to silence the compiler; fix isolation with actors or value types.
- Audit check-then-act sequences that cross an `await`: state can change during the suspension, so assumptions made before it may no longer hold (WWDC21 session 10133, SE-0306). After the suspension, revalidate invariants and preserve the repo's cancellation, generation, and identity checks before acting on pre-await state. Not every such sequence is a bug, and capturing results into locals does not by itself prevent publishing stale results; review needs lifecycle reasoning, not a blanket rewrite.

## Cancellation

- `catch` blocks filter out `CancellationError` before handling other errors. Cancellation is a normal lifecycle event, not an alert.
