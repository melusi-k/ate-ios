# #195 second slice: real seeded shopping/diary destinations

Source: https://github.com/melusi-k/ate-ios/issues/195
Branch-only from6f9fe56fc3fc3a8a544d79450006592a6316b375.

DEBUG plus -UITesting plus -qaInsightDestinations creates three synthetic pending
shopping items across two named QA recipe sources and three unknown-nutrient diary
records today. No cooking/Health/meal inference, personal records or model payloads.
Real deterministic engine derives shopping and diary candidates; no fake candidate
or fake destination. QA diary uses its own defaults suite; same repository reaches
AppStore and real legacy diary route without reseeding on navigation. Canonical
runtime combinations fail explicitly, not silently mixing owners. Without the QA
flag ordinary repository selection is unchanged; release excludes this fixture.

Two new normal-text native acceptance journeys assert evidence, selected Shopping
or Settings/real diary route, actual synthetic pending item/three diary rows,
return through Journal, and unchanged suggestion retention. Six retained captures.
One required unit checks synthetic evidence eligibility, action registry choices
and no nutrient claims. All earlier required unit entries/7UI selectors remain;
two UI selectors appended to existing Insights job. No new runner, dispatch,
retry, timeout increase or removed assertions. Three Python source contracts guard
fixture scope, shared QA diary destination and additive test selection.

210PythonPASS; Swift grammar/diff-checkPASS. Native compilation/typecheck/warnings,
XCTest and pixels UNVERIFIED: no Xcode/simulator here. Reviewer must run exact-head:
InsightsAcceptanceUITests/testSeededShoppingInsightOpensRealListAndRetainsSuggestion
InsightsAcceptanceUITests/testSeededDiaryInsightOpensRealDiaryAndRetainsSuggestion
and inspect six screenshots. A selector/arrival failure is evidence to diagnose,
not permission to add navigation retries or weaken assertions. This does not
qualify canonical runtime, cross-domain refresh, device behavior or all #195.
No production activation, issue closure, PR, publish, merge or CI dispatch.
