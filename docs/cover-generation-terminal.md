# Terminal cover generation + settled Explore fixture

Base: `ef58846bf8e2ab54b3abfc09e39264187d7cd1cc` (main after #653). Supersedes the rejected
`fix/cover-backfill-uitest-gate` packet (global isUITesting early return): that approach removed
remote download/page-image paths from every UI test and left the real device defect unfixed.
Round 2 supersedes the first deadline packet: its `save(...)` sat inside the race closure, so a
result arriving after the deadline could still write a cover, and both racer tasks were orphaned
with no cleanup. Round 3 supersedes round 2: the boundary tests copied the token/commit logic
into local arrays (removing the production guard would not have failed them), the availability
check ran outside the deadline, and ResumeBox was a local type inside a generic function.
Round 4/5 supersede round 3: the test harness needed UIKit/@MainActor, the Boolean loading
marker let a superseded attempt (or an overlapping resolve's unconditional defer) clear a
running operation's shimmer, and the overlap test assumed ordering with sleeps.

## The red and its cause (unchanged analysis, pass/fail compared)

`ExploreUITests.testExploreDismissPreservesSelectedCollection` burns XCTest's 60s animation
cap exactly twice per run in passes and failures alike (pass ~144s total, fail >180s). The
only Explore test with `-qaExploreRetentionSaved`, its coverless fixture card (no
imageURL/sourceURL) reaches `CoverStore.generate`'s Image Playground stream, which never
settles on the CI simulator image: `loading` stays set, `Shimmer`'s repeatForever keeps the
app non-idle, and every interaction while the card is visible costs the 60s cap. The same
never-settling stream is a real device defect: on a user phone whose Playground generation
hangs (no model, warm-up stall), the shimmer never stops and the app never idles.

## Product fix: terminal attempts, effect eligibility at the commit boundary

Production and commit are separated through three production seams the tests drive directly:

- `withTerminalDeadline(seconds:operation:)` races production against
  `generationDeadlineSeconds = 45` (first completion wins, via the file-scope generic
  `ResumeBox<T>` - a local type inside a generic function cannot capture the generic
  parameter) and returns only the produced CGImage; the closure writes nothing. Deliberately
  unstructured: a structured task group would still wait for a hung, cancellation-
  uncooperative system stream at scope exit.
- `beginCoverAttempt(for:)` issues a monotonic per-recipe token (`coverGenerationAttempts`);
  each begin supersedes earlier attempts.
- `commitGeneratedCover(_:attempt:for:)` is the single effect boundary: only a winning
  product (`guard let produced`) from the still-current attempt (token equality), re-proven
  against the writer epoch (`validateWriter()`), may call `save`. A product that arrives
  after the deadline has already lost the race (`produced == nil`), so it never reaches the
  guard; a superseded attempt fails the token check.
- `runCoverAttempt(for:seconds:produce:)` composes them: token, shimmer state, deadline
  race, commit. `generate` calls it with the Image Playground producer; the tests call it
  with synthetic producers, so what is tested is the production path itself.

Shimmer ownership is an explicit refcount (`loadingHolders`): `beginCoverLoading` /
`endCoverLoading` are the only writers of the `loading` marker and are called by both
`resolve` and `runCoverAttempt`. The marker clears only when the last holder releases, so
neither a superseded attempt that settles early nor an overlapping resolve's defer can
clear a running operation's shimmer. The attempt token now gates commit eligibility only;
loading no longer depends on it.

Cleanup is explicit: after the winner is known, the helper cancels both the timer (so a fast
success does not keep a 45s sleep alive) and the operation task. Cancellation is cooperative
only - if the system stream ignores it, that task ends unread; the helper retains nothing
after return and its captured state persists no longer than the system stream itself. That is
why the commit guard, not cancellation, is the late-write safety boundary.

The availability check is bounded too: `checkPlayground()`'s `ImageCreator()` init runs under
the same `withTerminalDeadline`, resolving to "availability check timed out" (tile fallback)
instead of an unbounded await, so the 45s bound covers every Image Playground init and stream
in the cover path.

All existing semantics are unchanged: the attempted marker, the `wasLoading` guard, the epoch
re-check, remote download/page-image paths, and error handling. On deadline the attempt
reports failure (nil), the existing `defer` clears `loading`, the shimmer stops and the
branded tile - the designed fallback - remains.

Native behavior coverage (AteTests/CoverTerminalDeadlineTests.swift, full unit lane) - every
attempt-behavior test drives the production seams, so deleting the production guard fails the
test:

- helper: a never-settling operation terminates nil near the deadline; a settling operation
  returns its value; a failing operation settles immediately;
- **deadline then late completion** (`runCoverAttempt` with a 1s deadline and a
  cancellation-resistant producer that completes at 2s): the attempt returns nil, `loading`
  clears at the terminal state, and after the product fully materializes the generated cover
  file still does not exist;
- **superseded attempt** (`beginCoverAttempt` twice, then `commitGeneratedCover` with each
  token): the stale token commits nothing and writes no file; the current token commits;
- **epoch rejection**: with `validateWriter` throwing, `commitGeneratedCover` returns nil and
  writes no file;
- **loading cleared on failure** (`runCoverAttempt` with a producer that returns nil
  immediately): nil result, shimmer state cleared, no file, no 45s wait;
- **attempt overlap** (two concurrent `runCoverAttempt` calls for one recipe, ordering
  proven by producer-entry and release gates - both attempts are inside their producers
  before the older is released; no sleeps): while the newer attempt runs, `loading` stays
  set after the superseded attempt terminates; the last holder clears it;
- **resolve/attempt nesting** (a full `resolve(allowGenerate: false)` call runs while an
  attempt is proven inside its producer): resolve releasing its own hold does not clear the
  attempt's shimmer; on the old unconditional defer this fails. Thread.sleep remains only
  where it simulates an uncooperative producer (the deadline-late test).

## Fixture fix: a real settled state, not a bypass

`ExploreRetentionQAFixtures` sets the fixture card's `coverImage` to `CoverStore.removed`
("none") - the product's actual user-removed-cover state: branded tile, no backfill attempt,
per existing `ensure` semantics. Scope honesty: the settled-fixture fast pass validates the
retention journey only; the production shimmer fix is proven by the deadline unit tests above,
not by the Explore test. Every other recipe and UI test keeps the full lazy-backfill behavior,
including remote download, page image and generation. The existing fixture pin
(`test_explore_bounded_retention.py`: no query fill, no Explore skip, no favorites) still
passes unchanged.

## Evidence and pins

- `Ate/Services/CoverStore.swift` forward `a46949930076...`;
  `Ate/App/ExploreRetentionQAFixtures.swift` forward `6e16f8ed2bd8...` (full hashes in inverse JSON).
- `scripts/tests/cover_generation_terminal_delta.py` + `cover_generation_terminal_inverse.json`
  (fixture SHA `66d59c2164b586d018d0317fd8d1824fbaf306cd1c8b2b8a06cf173de95c38ab`) restore both
  files byte-for-byte to their historical hashes (`8c7d0dea...`, `1cf24d26...`).
- `scripts/tests/test_cover_generation_terminal.py` pins: the seam structure (generate and
  the runner contain no `save`; the commit seam's guard ordering, guard before save; the
  runner's token/deadline/commit composition); the helper's non-structured, single-resume,
  loser-cancel design with ResumeBox at file scope (no local type in the generic function); the
  runner's refcount loading ownership (no first-insert flag, no token-based cleanup);
  the bounded availability check; unchanged backfill paths (no isUITesting gate anywhere in
  CoverStore); the fixture's real settled state; the nine native tests;
  `AteUITests/ExploreUITests.swift` byte-untouched
  (`5b25d18ee574c5436c77471830a6f21ca6b7976227be9d74239a3fbdf4e0680c`); exact inverses.
- 515 Python PASS, check-ids 181 consistent. Workflows, project.yml, full-unit-required.txt
  unchanged; no timeout, retry or expectation changed in any test.
- Native acceptance on the PR head: full unit lane gains the nine deadline/boundary/seam tests;
  presentation-creation's Explore test loses both 60s stalls (fixture settles immediately)
  and should finish in ~25s. Real-device cover generation keeps working with a 45s bound.
