# CI infrastructure and test-runner lifecycle

Central record of how Ate's GitHub-hosted CI runners move a job from allocation
to cleanup, what we have actually measured at each stage, and where the known
gaps are. Created 2026-11-01 at the project owner's request so that
infrastructure and test-runner failures are tracked in one place instead of
being reconstructed from scattered logs.

This document is a record, not policy. CI architecture and lane policy live in
[docs/CI.md](CI.md); the product lifecycle framework lives in
[PRODUCT_LIFECYCLE.md](../PRODUCT_LIFECYCLE.md). Nothing here changes gates,
triggers, or provisioning.

## Reading rule: measured vs inferred

Every entry states its basis:

- **Measured** - taken from a cited run, log, artifact, or commit on a specific
  date. Numbers are exact for that run only; one run establishes no envelope.
- **Inferred** - a conclusion drawn from evidence but not directly observed.
- **Open** - not established by any evidence we hold.

Dates are UTC. Run links point at the workflow run that owns the evidence.

## Lifecycle stages

Stages below follow the journal open-state UI lane
(`.github/workflows/journal-open-state-ui.yml`, issue
[#245](https://github.com/melusi-k/ate-ios/issues/245)), the lane where the
current failures occur. The compile and dogfood lanes share stages 1-4 and 7-8.

### 1. Runner allocation

- **What happens:** GitHub assigns a hosted `xcode-27` macOS runner (3 CPU).
  Queue time is pool-dependent and varies widely.
- **Measured:** job start vs run start gaps of seconds to ~20 minutes observed
  across 2026-11-01 runs. Compile jobs: 58s-2m warm builds once started;
  36m02s on a cold-cache run (run
  [41324647020](https://github.com/melusi-k/ate-ios/actions/runs/41324647020)).
- **Open:** whether pool contention contributes to any in-job stall. No
  evidence either way; pool economics are unmeasured.

### 2. Checkout, caches, simulator selection

- **What happens:** checkout, Homebrew cache restore, then
  `scripts/select-ios-simulator.py` picks one simulator UDID (`SIM_ID`) used by
  every later step of the job.
- **Measured:** on run
  [41333393387](https://github.com/melusi-k/ate-ios/actions/runs/41333393387)
  (2026-11-01, green), `SIM_ID=B6BCFC3D-3ADD-42C8-BB29-33FF8FE7E0B0`; testing
  phase began 17:51:39.6 (`644.521 elapsed` closed at 18:02:24.106).
- **Note:** all gates in the AI model lane share one job's `SIM_ID` by design
  (a readiness pass qualifies that machine only) - see docs/CI.md.

### 3. Build for testing

- **What happens:** `xcodebuild build-for-testing` for scheme Ate on `SIM_ID`,
  `CODE_SIGNING_ALLOWED=NO`.
- **Measured:** on run 41333393387 the test runner process existed ~75s before
  the test suite started (runner first log line 17:54:56.97; suite start
  17:56:12.244).

### 4. Test-without-building start (pre-launch)

- **What happens:** `xcodebuild test-without-building` with
  `-only-testing:AteUITests/JournalOpenStateUITests`,
  `-parallel-testing-enabled NO`, `-test-timeouts-enabled YES`,
  `-default-test-execution-time-allowance 240`,
  `-maximum-test-execution-time-allowance 480`.
- **Measured (green run 41333393387):** 17:51:39.6 testing start ->
  17:54:56.97 runner "Running tests" -> 17:56:12.244 suite start. About 4.5
  minutes of pre-launch setup on that run.
- **Open:** the breakdown of that 4.5 minutes (destination checks, DerivedData
  state, simulator boot) is not measured per stage.

### 5. App install and launch (fork)

- **What happens:** XCTest requests the app launch; the app process forks
  under the job's simulator device directory.
- **Measured (green run 41333393387):** first launch at 17:56:13.7 (suite
  start 17:56:12.245 + t=1.50s).
- **Measured (red runs):** on run
  [41307451213](https://github.com/melusi-k/ate-ios/actions/runs/41307451213)
  (2026-11-01), the pre-fork interval reached ~153-175s before the app process
  appeared; a host spindump ~75s into the stall showed no Ate process at that
  sampled instant (a single sample does not establish absence across the
  interval).
- **Open:** what holds the launch request in red runs. The green launch-to-fork
  envelope is unmeasured; no mediation-daemon state has been captured during a
  stall.

### 6. XCTest connection (automation session attach)

- **What happens:** the runner sets up the automation session with the app;
  only then do test assertions run.
- **Measured (green run 41333393387):** launch-to-session times per test:
  29.31s / 1.48s / 1.49s / 2.06s (xcodebuild t= stamps). Green
  launch-to-session envelope observed so far: 14-49.14s.
- **Measured (red runs, two distinct failure phases, not to be conflated):**
  - Pre-assertion launch timeout: run 41307451213,
    testHealthyOpenShowsNoBanner died at 140.7s with an XCTest-internal launch
    timeout, before any assertion.
  - Mid-test execution-allowance death: PR #260 journal run
    [41297742575](https://github.com/melusi-k/ate-ios/actions/runs/41297742575)
    attempt 1 died 4m40s+ into the test (240s allowance, timeout-compatible).
- **Open:** whether the two phases share a cause. Failures are observed on 4+
  heads; no single branch's content explains the pattern; runner/environment
  variability is the common factor. Root cause stays open.

### 7. Test execution

- **What happens:** the four open-state tests run sequentially; each taps
  Library -> libraryBrowseMenu -> Journal and asserts the banner state.
- **Measured (green run 41333393387):** durations 53.073 / 21.927 / 150.356 /
  145.155s; suite 4/4 in 370.511s. The two slow tests each hit exactly two
  ~60s "App animations complete notification not received" caps (recovered at
  t=74.43 and t=136.35; unavailable at t=75.14 and t=136.42) on the
  Library -> Journal route; the waits then completed and assertions passed.
- **Inferred:** the ~60s caps are a post-attach transition family, distinct
  from the launch-mediation family: bounded, non-fatal on this run, and located
  after session attach on a specific navigation route. The log shows the
  notification was not received within 60s; it does not show the app's internal
  animation state, so the internal cause is open.
- **Open:** why the animation-complete notification is not received on that
  route. Reproduced on 2026-11-01; unresolved.

### 8. Teardown, result bundle, artifacts, cleanup

- **What happens:** result bundle written to `$RUNNER_TEMP`, rendered
  screenshots exported, diagnostics uploaded with `if: always()`, runner
  released.
- **Measured:** artifact journal-open-state-ui-97 (id 13094487486, 5,856,872
  bytes) for run 41333393387 contains the full log, screenshots, xcresult, and
  watcher outputs. Build IPA artifacts (for main pushes) are separate, e.g.
  Ate-0.1.347-build347-TierA.ipa from run
  [41328117329](https://github.com/melusi-k/ate-ios/actions/runs/41328117329).

## Failure family register

| Family | Stage | Signature | Status |
| --- | --- | --- | --- |
| Launch mediation stall | 5-6 | 153-175s pre-fork; XCTest launch timeout at ~140s, or 240s allowance death | Open; intermittent across 4+ heads; last run (41333393387) did not reproduce |
| Transition idle-notification | 7 | Two ~60s "animations complete" caps on Library -> Journal per affected test | Reproduced 2026-11-01; bounded and non-fatal in that run; cause open |

## Instrumentation record

- 2026-11-01: an observation-only launch watcher was added to the journal
  workflow (commit `69fe2ffd`, branch for issue #251). It arms a background ps
  series and up to two spindumps (1 pre-fork at T+90, 1 reserved post-fork at
  fork+30s), and never signals app, test, or xcodebuild processes. Completed
  captures land in `watcher-accepted/`; only that directory is uploaded.
- **Measured fault in its first run (41333393387):** the watcher's T+10 ps
  header was written at 17:56:26, but the snapshot's own etimes (xcodebuild
  06:09, runner 03:38, recovered-app 00:18) place the actual capture at
  ~17:57:48 - an ~82s blockage before or during `ps`, inside the launch window
  it was meant to sample. Cause open: the artifacts do not distinguish process
  enumeration cost from scheduling delay. Consequence: watcher T+ labels are
  header times, not sample times, and its "~T+10 attach" record is invalid;
  the true first attach was 29.31s by xcodebuild's own stamps.
- **Reading rule for watcher output:** check snapshot etimes against the
  header epoch before trusting any T+ label.

## Known gaps (tracking list)

1. Launch-mediation cause: no pre-fork or mediation-daemon capture from a red
   run exists yet.
2. Green launch-to-fork envelope: unmeasured (only launch-to-session is).
3. Pre-launch stage breakdown (stage 4): ~4.5 minutes unaccounted per stage.
4. Transition idle-notification cause on the Library -> Journal route.
5. The ~82s ps blockage cause (stage instrumentation itself).
6. Watcher scope covers only the first launch; stalls on later launches are
   unobserved.

## Maintaining this document

- Append dated entries; do not rewrite history. Corrections get their own
  dated entry that names what was wrong.
- Keep the measured/inferred/open labels honest. A green run is one sample,
  not an envelope; a pass does not close a failure family.
- Link every number to its run, artifact, or commit.
