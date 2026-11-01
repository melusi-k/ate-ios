# Verification Records

This directory stores candidate-specific verification evidence. Each record is an auditable snapshot and must never be silently rewritten after a release decision.

## Rules

1. One record per candidate build/release decision. Use a stable filename such as `YYYY-MM-DD-build-N-<short-sha>.md`.
2. Record the exact full Git SHA, app version/build, channel, backend environment and device/OS conditions.
3. Link the actual workflow runs, QA matrix evidence, manual results and retained artifacts. Do not paste secrets, personal data or private user content.
4. Distinguish Pass, Failed, Blocked, Not run, Skipped and Partial. Missing evidence is not a pass.
5. A passing check from another SHA/build is historical context only.
6. Record the human release decision, decision-maker, timestamp, restrictions and known issues.
7. Once a decision is made, treat the record as immutable. Correct errors with a dated addendum or superseding record that links back to the original.
8. Do not create a record containing guessed values. Use `Unknown` and assign an action to resolve the gap.

## Candidate record template

Copy to a new dated file for each candidate.

```markdown
# Verification Record — <version> (<build>)

- Record status: Draft / Reviewed / Superseded
- Candidate created:
- Git SHA (full):
- Version / build:
- Release channel:
- Backend environment and migration state:
- Candidate artifact / distribution link:
- Verification owner:
- Release decision owner:

## Candidate conditions
- Xcode / toolchain:
- Simulator/device and OS:
- Locale / region:
- Account, entitlement and model-readiness prerequisites (no credentials):
- Feature flags / configuration:

## Automated evidence
| Check / acceptance IDs | Workflow run / artifact | Result | SHA/build match | Notes |
|---|---|---|---|---|

## Manual and device acceptance
| Acceptance ID / journey | Device / OS | Tester / date | Result | Evidence link |
|---|---|---|---|---|

## Failures, blocks and exclusions
| Item | State | Impact | Owner / resolution |
|---|---|---|---|

## Known limitations and risk
- 

## Release decision
- Decision: Eligible / Not eligible / Conditional
- Decision-maker and timestamp:
- Conditions / restrictions:
- Rationale:

## Addenda
- <date>: <correction or later evidence; preserve original decision>
```

## Relationship to existing QA

The authoritative acceptance definitions remain in [docs/MVP_CHECKLIST.md](../docs/MVP_CHECKLIST.md) and [docs/QA_MATRIX.md](../docs/QA_MATRIX.md). The record captures results for one candidate; it must not become a second acceptance inventory or replace existing launch gates.
