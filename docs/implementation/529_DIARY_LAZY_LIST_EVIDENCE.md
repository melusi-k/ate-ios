# #529 diary destination materialization

Base: 43589115e449e4fbb405f883e0a551a0be220999.

The final-head raw test reaches Food diary with exactly one navigation bar, then
fails on InsightsAcceptanceUITests.swift:516 before any scroll. Its retained
screen recording and AX tree show Diary date, Daily totals and This week.
NutritionDiaryView places the meal sections after those totals in a lazy List.
The absent entry nodes are not proof of an absent fixture or failed route.

The journey now requires one mounted content CollectionView and scrolls that
actual diary list to materialize the three fixture records. The existing
first-row, exact count of three, named-food, Settings back-route and retained
suggestion assertions stay unchanged. No production code, launch fixture,
wait duration, CI selection or retry policy changes.

The pre-action image also shows a partially clipped diary carousel card. That
does not explain this assertion: the subsequent Food diary arrival passes.
This packet does not claim to fix unrelated carousel composition.

Verification: source guards and Python suite, Swift grammar parse, diff check.
Native build, simulator replay and updated pixels remain required and unrun.
Other #529 assertion and allowance failures are separate work.
