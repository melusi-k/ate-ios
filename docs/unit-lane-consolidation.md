# One full exact-head unit lane

Compile/build-nutrition runs all AteTests once after its existing exact-PR-head build, using test-without-building. Its existing 45-minute job budget and per-test allowances are not increased. The former Dogfood unit step had a separate 20-minute cap; that cap no longer applies after moving units into this existing combined 45-minute job. No additional Mac job or paid capacity is added. The App Clip scheme remains separately built and tested. Existing Compile regression and final gate contexts remain unchanged.

The selector ledger accounts for all eleven former focused Compile unit selectors and Dogfood's full AteTests selection. Twenty-five existing CatalogueIntegrity/NutritionDiary/CookSession named-pass assertions move to the full unit log. The mixed ingredients step keeps its three required UI pass assertions and normal-size exclusions. No UI selector, critical-flow test, per-test allowance or quarantine assertion is removed. Full units reject a missing/zero executed count and a nonzero test command status. Logs and xcresult upload before nutrition UI execution.

The two #89 fixture selectors were advisory in Compile but already strict in Dogfood's full AteTests. They remain included in the strict full unit suite; removing the duplicate focused diagnostic does not waive their failure. Their historical diagnostic failures are not recast as passes. The old focused recipe-generation and library-layout issue-reporting calls are removed with their old logs, rather than pointing them at an unrelated full-suite failure. Full-suite failures retain their complete log and xcresult; this changes automatic per-issue reporting for those two focused log paths, not the failure gate.

Dogfood checks out the exact proposed head instead of the synthetic PR merge ref. It retains critical flows, Library popup/reorder journeys, photo-phase diagnostics and the non-qualifying testQA7_SyncAccount quarantine. It no longer executes or claims a local unit result. Its summary explicitly routes unit acceptance to Compile. Dogfood may complete its distinct critical-flow gate while units fail in Compile; that is not whole-PR qualification. The existing Compile final gate still blocks when build-nutrition/full units fail.

Nutrition UI runs for diagnostics after a unit failure if the build succeeded. That cannot erase the failed unit step or make the job pass. Other UI workers remain parallel. The current Journal workflow is unchanged; its branch-only bounded unit diagnostics and optional/manual/release workflows are outside this active Compile/Dogfood deduplication.

Budget evidence, not a runtime guarantee: retained PR400 build-nutrition was 34m01s including 2m08s focused units and 19s duplicated Python. Its Dogfood full-unit step took 8m13s including another build. A conservative replacement estimate is 39m47s, leaving 5m13s within the existing 45m budget. The runs use different head/merge-ref contexts, so this is a fit estimate, not measured candidate performance. The new lane uses its existing build. If ordinary CI approaches or reaches the cap, keep the result red and stop for review; never raise the budget or retry around it.

Retained timing sources:
- https://github.com/melusi-k/ate-ios/actions/runs/42646407841/job/129260814918?pr=400
- https://github.com/melusi-k/ate-ios/actions/runs/42646407874/job/129260813473?pr=400

No merge-ref unit-coverage claim is retained. This design qualifies the exact proposed head; it does not prove that head and merge ref are identical. No required-check name, repository rule, trigger, release/promotion gate or app runtime behavior changes.
