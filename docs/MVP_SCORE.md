# MVP score — historical record

This file preserves the previously recorded build-36 Tier A/B score as historical context only. It is **not** the current release-readiness score and must not be used to imply that current requirements pass.

The active backlog is [PRODUCT_BACKLOG.md](PRODUCT_BACKLOG.md), acceptance definitions are in [MVP_CHECKLIST.md](MVP_CHECKLIST.md), and current per-ID verification evidence belongs in [QA_MATRIX.md](QA_MATRIX.md).

## Historical snapshot (build 36)

| Former commitment group | Historical score | Historical percentage |
|---|---:|---:|
| Tier A — internal pilot | 27 / 44 | 61% |
| Tier B — wider/public launch | 4.5 / 13 | 35% |
| Tier C — former polish inventory (corrected denominator) | 0 / 67 | 0% |
| Former aggregate denominator (historical; not a current score) | 31.5 / 63 | 50% |

The former aggregate mixed incompatible denominators and is retained only to explain the historical record. **Do not recompute or publish a new score until all 179 acceptance IDs have been reconciled against current tests, workflow results, and required manual/device evidence.**

## Current scoring policy

- Score from evidence attached to the exact candidate commit, not from source presence, issue labels, accessibility setup flags, or a green non-blocking workflow alone.
- Keep Not run, Blocked, Failed, Skipped/not discovered, and Quarantined/non-blocking distinct from a pass.
- Recompute only with one verified denominator, with device/production checks kept separate from simulator/CI checks.
- The release owner makes the explicit go/no-go decision against the current definition of done in [issue #45](https://github.com/melusi-k/ate-ios/issues/45); an aggregate percentage alone never approves a release. The proposed thresholds and must-pass rows in [LAUNCH_GATES.md](LAUNCH_GATES.md) are advisory and are not current policy until the owner approves them.
