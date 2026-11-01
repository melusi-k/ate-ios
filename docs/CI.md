# CI execution policy

## Standard iOS simulator target

All simulator-based CI test jobs use the GitHub-hosted `xcode-27` runner image with Xcode 27.1 and the **iPhone 18 Pro simulator on iOS 27.0**. The shared selector `scripts/select-ios-simulator.py` requires that exact device/runtime pair and fails with an actionable diagnostic if it is unavailable; it never silently falls back to an older iPhone or a different iOS runtime. This keeps PR qualification, focused regressions, nightly QA, pre-production validation and full-validation UI shards on the same device profile. The simulator target is an execution environment only and does not change the app's iOS 18 deployment target.

## Full-validation UI shard concurrency

The full-validation UI suite is split into four independent GitHub Actions matrix jobs:

- `AteUITests`
- `CoverageUITests`
- `AccessibilityAuditUITests`
- `WidgetsIntentsUITests`

Each shard job runs on its own `xcode-27` runner. Within each job, Xcode is configured for **two simulator test workers**:

```sh
-parallel-testing-enabled YES
-parallel-testing-worker-count 2
```

This policy is applied consistently to the full UI shard matrix in:

- `.github/workflows/build-ipa.yml` — deliberate full validation / beta-promotion path.
- `.github/workflows/preproduction-qa.yml` — pre-production release-candidate validation.

The four-way GitHub Actions matrix remains unchanged. Two workers means up to two Xcode-managed iPhone 18 Pro simulator test workers **inside each shard job**; it does not mean one shared simulator across shards, nor does it increase the number of matrix shards. If all four shard jobs run concurrently, the matrix can therefore schedule up to **eight simulator test workers across four Xcode 27 runners**.

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

## Apple Intelligence / Foundation Models lanes (decision, 2026-11-01)

Ate validates AI features in three lanes. Adopted by the project owner on 2026-11-01 as a formal CI architecture decision, implemented as part of the existing CI governance work.

### 1. Standard CI lane (existing runners, unchanged)

- Build and compile validation, unit tests, UI automation.
- Foundation Models **unavailable-state** tests and mock-based deterministic tests stay in this lane.
- No changes to ordinary build/UI test runner allocation. The four-shard, two-worker full-validation UI strategy above is unchanged.

### 2. AI-ready real-model lane (eligibility required)

- Workflow: `.github/workflows/ai-model-lane.yml`, independently visible job `ai-model-preflight`.
- Preflight checks `SystemLanguageModel.default.availability` and requires `.available`.
- It then executes a small **real** generation request and validates that inference completes.
- It fails explicitly on device ineligibility, disabled Apple Intelligence, or model-not-ready. It never silently substitutes a mock and never skips to green.
- **Same-device rule:** the readiness check, the generation smoke and the lane's real-model tests execute in one job on one simulator UDID, as ordered job steps: GATE 1 (availability) must pass before GATE 2 (inference smoke) runs, and evaluation suites run only after GATE 2. Step ordering is the gating mechanism - it does not rely on XCTest method order. A preflight pass on one machine never qualifies another machine.
- Failure messages identify the exact condition via structured prefixes: `AI-LANE ELIGIBILITY`, `AI-LANE READINESS`, `AI-LANE INFERENCE`, surfaced as per-condition job annotations from the test log.
- Inference is bounded: test execution allowances (240s default / 480s max) fail a hung generation through the same annotation path.
- Preflight implementation: `AteModelReadinessTests` (separate test target; no standard-lane `-only-testing` filter selects it, so ordinary lanes never execute it).
- Real-model evaluation tests join this lane as they land; today the lane runs the preflight + inference smoke.
- Trigger and merge-gate policy for this lane is the owner's pending decision; it is manual-dispatch only until adopted. AI-ready runner provisioning remains subject to the owner's approval.
- Measured evidence (2026-11-01, PR #260 lane run): on the GitHub-hosted `xcode-27` config, availability returned `.unavailable` with reported reason `modelNotReady`; the lane failed GATE 1 with that structured reason and skipped the inference smoke. The availability enum reports a single reason, so this run alone does not establish that device eligibility checks passed. Simulator inference requires macOS Tahoe on the host with Apple Intelligence enabled and the model downloaded (Apple DTS: https://developer.apple.com/forums/thread/815397; availability reasons: https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason). No supported readiness route is verified for the hosted VM; a physical Apple-Intelligence-enabled Mac or a physical device is the verified Apple-supported shape. AI-ready runner provisioning remains subject to owner approval.

### 3. Physical-device quality lane (iPhone)

- Real-device inference validation, response quality and correctness, latency/performance, memory and stability observations.
- Current route: the owner's iPhone with sideloaded dev builds.

### Preflight verdicts

| Condition | Expected result |
| --- | --- |
| `.available` | Continue to generation smoke |
| `deviceNotEligible` | Fail eligibility |
| Apple Intelligence disabled | Fail eligibility |
| Model not ready | Fail readiness |
| Generation fails or times out | Fail inference |
| Real generation succeeds | Pass |

### Standing acceptance criteria

1. No changes to ordinary build/UI test runner allocation.
2. Existing unavailable-state coverage remains active.
3. Real-model tests cannot pass through mock substitution.
4. The real-model lane has an independently visible CI result.
5. Failure messages identify the exact availability or inference failure.
6. AI-ready runner provisioning remains subject to owner approval.
7. Simulator requirements and the physical-device testing strategy are documented here and kept current.
