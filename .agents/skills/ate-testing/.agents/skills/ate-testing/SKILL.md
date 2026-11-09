---
name: ate-testing
description: Use when adding tests, diagnosing XCTest or simulator failures, changing test infrastructure, or assessing integration and UI-test evidence.
---

# Ate testing and verification

## Diagnose before changing

1. Identify the exact workflow, test, target, simulator, run, job, attempt, and failing step.
2. Separate application regressions from simulator, runner, XCTest, signing, boot, launch, and automation infrastructure failures.
3. Preserve timestamps and raw failure evidence; compare passing and failing attempts.
4. Reproduce with the narrowest useful test before broadening the run.
5. Do not infer a root cause from a timeout symptom alone.

## Test design

- Add focused unit tests for deterministic domain and service behavior.
- Use integration tests for boundaries such as persistence, sync, and cross-module flows.
- Use UI tests for user-visible journeys and navigation behavior.
- Assert observable outcomes and stable accessibility identifiers; avoid arbitrary sleeps.
- Keep test setup isolated and deterministic. Clean up state created by a test.
- Do not weaken assertions, skip failing tests, or increase timeouts merely to hide an unexplained failure.

## Evidence standards

Report separately:
- Build result
- Unit-test result
- Integration-test result
- UI/simulator journey result
- Physical-device result
- CI infrastructure health

Include exact run/attempt identifiers and artifacts when available. A green subset of journeys is not full feature acceptance. State limitations and unverified paths explicitly.
