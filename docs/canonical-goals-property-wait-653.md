# Canonical goals readiness observation candidate (#653)

## Evidence and limits

The first ordinary Journal run on eb030bd2 (45004218346, artifact14748526792) executed27 tests with one failure and no skips. Manual reflection CRUD now passes, including delete-alert Cancel. The sole red is `CanonicalUpgradeUITests.testTypedGoalsReadsAndSavesIsolatedRuntimeDomainAcrossRelaunch`, at the five-second enabled-state expectation after relaunch.

The app handoff is valid: the old app PID37302 exits, and the new app PID38290 serves the queries. Switch existence returns the Energy switch with value0 and no query error at09:04:20.996Z. The generic enabled waiter starts09:04:21.004Z, its first find begins22.168Z, the app captures AX snapshot data by22.772Z, and matching-tree processing is still in progress at26.090Z. The runner interrupts the query and reports timeout at26.286Z; the matching reply is logged at26.843Z, after the deadline. There is no observed false enabled attribute. The last decoded recording frame is earlier than the failing property read. OFF is not disabled.

The same TypedGoals case passed on f6949 in41.640s, with its property find taking about0.146s rather than the current interrupted4.116s. The other three CanonicalUpgrade cases pass on eb030. No CanonicalUpgrade case calls the delete-alert snapshot helper. This is not the earlier stale unit-host PID launch failure.

Current run: https://github.com/melusi-k/ate-ios/actions/runs/45004218346
Previous run: https://github.com/melusi-k/ate-ios/actions/runs/44999800313
Apple native property-wait documentation: https://developer.apple.com/documentation/xcuiautomation/xcuielement/wait(for:toequal:timeout:)
Apple property-wait example: https://developer.apple.com/videos/play/wwdc2025/344/

## Narrow candidate

Replace the generic NSPredicate/XCTWaiter enabled check with the direct XCUIElement property waiter for `isEnabled == true`, keeping timeout5 exactly. Record start uptime, returned Boolean, and elapsed time. On false, take a screenshot before the still-failing assertion. A false result never reaches the persistence assertions as a pass.

The named switch binding, ten-second existence check, initial isolated value2345, real clear/save/terminate/relaunch journey, saved value0 assertion, missing energy-field assertion, and all other test bodies remain exact. No app-target source, workflow, selection, skip, retry, timeout allowance, required-native manifest, or shared snapshot helper changes. No arbitrary first match or pre-relaunch cached state is substituted.

This is a test-observation candidate, not a demonstrated product correction. The native API is supported by the current Xcode family, but native compile preflight and the new head's first ordinary run must qualify it. The API's internal polling schedule is not claimed here. It may still fail if its query cannot complete within the same five-second limit.

## Source guards and qualification

A pinned inverse restores all three changed pre-existing files exactly to eb030 before historical guards. Every historical inverse JSON remains byte-identical. Six new Python source-contract tests check the exact inverse, unchanged journey, same property/value/cap, single-result diagnostics and failure-only screenshot, protected hashes, and rejection of weaker/longer waits.

Python507 passes locally. This is not native proof. No native test is added or removed: expected counts remain Journal27 and AteTests1354, including the same eight mandatory unit cases. Native compile and runtime are pending. No rerun, waiver, timeout increase, or merge is requested.
