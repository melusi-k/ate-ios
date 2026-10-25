# Ate Test Coverage Report

**Status:** Baseline / evidence gathering  
**Scope:** `AteTests` and `AteUITests` as declared in `project.yml`  
**Last reviewed:** 2026-10-25

## Executive summary

Ate has separate unit and UI test targets. CI runs the unit suite and multiple UI shards, but the currently reviewed workflow evidence does not establish a published source-code coverage report or a 100% coverage threshold.

The available failure records for [#157 — CoverageUITests](https://github.com/melusi-k/ate-ios/issues/157) and [#158 — AteUITests](https://github.com/melusi-k/ate-ios/issues/158) include assertion failures. Therefore, the UI suite is **not demonstrated as fully passing** by the available evidence.

**No 100% coverage claim is currently supported.** The measures below are tracked separately because they answer different questions.

## Coverage measures and current evidence

| Measure | What it means | Current status |
|---|---|---|
| Test execution | Which tests were discovered and actually executed, passed, failed, skipped, or not run | Partial workflow/shard evidence; requires a fresh complete run and consolidated counts |
| Requirement-to-test mapping | Which product acceptance requirements have meaningful automated/manual test evidence | Tracked in the QA/acceptance work; not proven complete by test counts |
| Source line coverage | Executable production source lines exercised by tests | Unknown: no reviewed report establishes a percentage |
| Source branch coverage | Conditional paths exercised, where supported by the chosen instrumentation/reporting | Unknown: no reviewed report establishes a percentage |
| Assertion/behavioural coverage | Whether tests assert meaningful outcomes, edge cases, errors and recovery | Requires test-by-test review; line coverage alone cannot establish it |
| CI reliability | Whether required suites/shards execute on the exact candidate SHA and retain evidence | UI failure reports exist; current fully passing UI result is not established |

## Test target inventory

The repository's `project.yml` declares:

- **`AteTests`** — `bundle.unit-test`, sources from `AteTests`, dependent on `Ate`.
- **`AteUITests`** — `bundle.ui-testing`, sources from `AteUITests`, targeting `Ate`.
- The `Ate` scheme includes both targets.

The repository also declares `AteClipTests` separately. This report's initial scope is the two requested targets; coverage for other targets should be explicitly reported as out of scope, not silently included in an app-wide percentage.

## Known evidence and limitations

- [#157 — Full UI shard: CoverageUITests](https://github.com/melusi-k/ate-ios/issues/157) records assertion failures, including missing expected UI elements and a bottom-bar overlap assertion.
- [#158 — Full UI shard: AteUITests](https://github.com/melusi-k/ate-ios/issues/158) records UI-shard assertion failure evidence.
- [#183 — Audit AteTests and AteUITests for measurable 100% coverage](https://github.com/melusi-k/ate-ios/issues/183) tracks the full audit and follow-up work.
- [#70 — Requirements/QA mapping](https://github.com/melusi-k/ate-ios/issues/70) and [#138 — CI resilience and test execution](https://github.com/melusi-k/ate-ios/issues/138) are related workstreams.

This is an evidence-based initial report, not a claim that a fresh full-suite run or source-coverage export has already been performed. Historical results must be tied to their exact commit SHA and workflow run; they must not be represented as current-main results without verification.

## Required baseline run

Run the complete relevant test suites on one identified commit and controlled simulator destination. Retain the result bundles and logs.

Record at minimum:

- Audited commit SHA, workflow run URL, Xcode version, simulator/device and OS version.
- Test discovery counts and executed/passed/failed/skipped/not-run counts for `AteTests` and each UI shard.
- Result-bundle paths and exported coverage report artifact.
- Source line and function coverage for in-scope production targets, with the exact inclusion/exclusion policy.
- Branch coverage if the toolchain/report supports it; otherwise mark it unsupported/not measured.
- Every failure, quarantine, skip and non-blocking result, with links to the owning issue.
- Runtime and any shard aggregation/deduplication method.

## Coverage policy

1. **Execution is not coverage.** A test file existing does not prove its tests ran; skipped, quarantined, failed, or not-run tests are not counted as passes.
2. **Line coverage is not behavioural correctness.** Tests must assert meaningful outcomes, invariants and failure behaviour.
3. **Keep target and shard results distinct.** Report unit tests separately from every UI shard, then provide a consolidated view with duplicate-test handling documented.
4. **Define production scope.** Exclude test source and generated/build artifacts from production coverage. List any other exclusions and justify each one.
5. **Do not weaken gates to make the report green.** Diagnose whether failures are product defects, test-quality defects, or environment/runner failures, and preserve evidence.
6. **Set thresholds only after a measured baseline.** Add a repeatable report artifact and regression gate after reviewing current coverage and agreeing on justified exclusions.
7. **Make 100% claims precise.** Any future claim must name the metric, production target/scope, exact SHA, toolchain, exclusions, and retained report. Do not infer 100% behavioural or requirements coverage from 100% line coverage.

## Baseline results

| Field | Result |
|---|---|
| Audited SHA | Not yet captured for a fresh controlled baseline |
| `AteTests` execution counts | Pending baseline run |
| `AteUITests` / shard execution counts | Pending baseline run |
| Production line coverage | Not measured in reviewed evidence |
| Production branch coverage | Not measured in reviewed evidence |
| Coverage artifact URL | Not yet available |
| 100% threshold configured in CI | Not demonstrated in reviewed workflow evidence |

## Next actions

- [ ] Run complete `AteTests` on the exact audited SHA and retain `.xcresult` plus logs.
- [ ] Run all required UI shards on that same SHA/destination policy and retain each result bundle.
- [ ] Export and consolidate production-source coverage; document supported metrics and exclusions.
- [ ] Map production modules and acceptance requirements to tests and evidence.
- [ ] Triage #157 and #158 failures without treating failures as coverage passes.
- [ ] Review test assertion quality, uncovered lines/branches, and untested error/recovery paths.
- [ ] Add a CI-published coverage artifact and agreed regression threshold.
- [ ] Update this report with exact evidence links and before/after results.

## Acceptance statement

Until the baseline run, coverage export, and requirement mapping are available, source-code coverage and total requirements coverage remain **unknown**. The available UI-shard failures mean a fully passing UI suite has not been demonstrated. This report must be updated with retained exact-SHA evidence before any percentage or 100% claim is made.
