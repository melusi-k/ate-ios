# CI execution policy

## Full-validation UI shard concurrency

The full-validation UI suite is split into four independent GitHub Actions matrix jobs:

- `AteUITests`
- `CoverageUITests`
- `AccessibilityAuditUITests`
- `WidgetsIntentsUITests`

Each shard job runs on its own `macos-26` runner. Within each job, Xcode is configured for **two simulator test workers**:

```sh
-parallel-testing-enabled YES
-parallel-testing-worker-count 2
```

This policy is applied consistently to the full UI shard matrix in:

- `.github/workflows/build-ipa.yml` — deliberate full validation / beta-promotion path.
- `.github/workflows/preproduction-qa.yml` — pre-production release-candidate validation.

The four-way GitHub Actions matrix remains unchanged. Two workers means up to two Xcode-managed simulator test workers **inside each shard job**; it does not mean one shared simulator across shards, nor does it increase the number of matrix shards.

## Scope boundaries

Two-worker execution is limited to the four independent full-suite UI shard invocations above.

The following remain serial (`-parallel-testing-enabled NO`) for now:

- Everyday PR smoke and focused regression tests.
- `KeyFlowsQATests` and focused Settings/account-sync checks.
- Cooking Tracker and Cook Mode release regressions.
- Focused Health/journal, navigation, recipe-generation and widget-intents acceptance invocations.
- Unit tests and backend E2E (which are not part of this XCUITest worker policy).

Do not mechanically change every `xcodebuild test` invocation to parallel mode. A focused test may intentionally depend on ordered state, a shared fixture, a single simulator, or process-level setup. Expand scope only after demonstrating isolation and repeatable results.

## Rationale and resource guardrails

The four-way matrix already distributes independent test targets across separate runners. The additional lever is intra-shard parallelism: Xcode can schedule independent test cases on two simulator workers rather than executing the whole shard serially.

Two is the initial cap. Do not raise it without new evidence. More workers can increase simulator boot overhead, memory pressure, fixture contention and total runner consumption. A shorter shard duration does not automatically mean fewer billed macOS minutes because the worker pool runs within the same hosted job and may consume more resources.

The setting is intentionally explicit in both workflows rather than hidden in a shared script, so the release and pre-production gates remain easy to audit.

## Required evidence and monitoring

For each full-validation run, review:

1. All four shard jobs completed successfully and reported a non-zero executed-test count.
2. The `.xcresult` bundle and test log show no missing, skipped or unexpectedly duplicated tests; quarantined tests remain explicitly quarantined and are never counted as passes.
3. Failures are classified as product, test-quality or infrastructure issues. Do not retry or quarantine a failure merely to obtain green CI.
4. Simulator memory pressure, worker crashes, test timeouts and fixture collisions are checked in the job logs/artifacts.
5. Per-shard duration and overall full-validation critical path are recorded separately. Compare like-for-like candidate SHAs and equivalent test inventories; do not infer savings from unrelated runs.

The initial rollout is deliberately conservative. Review the first three successful full-validation executions and build a two-week timing/stability trend before considering any higher worker count or wider test scope. Treat speed improvement as unproven until the measurements support it.

## Rollback criteria

Revert the two-worker flags to `-parallel-testing-enabled NO` for the affected full-suite invocation if any of the following is repeatable or materially attributable to parallel execution:

- Tests fail only under parallel execution, or shared fixture/state collisions appear.
- A worker or simulator repeatedly crashes, hangs or exceeds the existing job/test timeouts.
- Memory pressure is sustained at warning/critical levels or causes instability.
- Test discovery/counts differ unexpectedly from serial execution.
- The overall full-validation critical path regresses materially without a compensating reliability or coverage benefit.

Rollback must preserve the four shard jobs, test inventory, diagnostics artifacts, aggregation and required release gates. Never make a failing test non-blocking, skip it, or weaken the release gate as a workaround.

## Controlled experiment

The serial-versus-two-worker experiment for `CoverageUITests` is tracked under [issue #138](https://github.com/melusi-k/ate-ios/issues/138). It uses one fixed candidate SHA, one build-for-testing, three serial and three two-worker trials, and captures result bundles, elapsed time and resource samples. The experiment is evidence for the decision, not a production workflow and must not be merged into the release workflows. Record its outcome on issue #138; do not claim a measured speedup until all trials and test counts have been inspected.

## Ownership of this policy

Changes to worker count or scope must update this document, both full-validation workflow invocations, the QA release instructions and the rollout evidence on issue #138 in the same pull request.
