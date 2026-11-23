# Mapped CI: dry-run inventory slice

Implements stage 1 of Discussion #662, additive on #661. It does not narrow test
execution, alter native gate requirements, change rulesets, or establish full-main
qualification. The existing workflows and test budgets remain unchanged.

## Files and evidence

- `ci/test-inventory.json`: source declarations in all four project test targets
  (AteTests, AteUITests, AteClipTests, AteModelReadinessTests) and Python tests.
  This is a source inventory, not a runtime discovery or pass ledger. Conditional,
  device-only and model-availability tests are retained; they are not claimed run.
- `ci/test-area-map.json`: explicit proposed path/area/selector associations.
  Test files map to their declared methods. Shared and unknown paths conservatively
  expand to the entire discovered native inventory. Coarse path rules are proposals,
  not a safe cutover policy. Missing/deleted selectors, duplicate selectors and empty
  mappings require review. Review assignment is a role requirement, not approval.
- `scripts/ci-mapping.py`: reads complete local merge-base-to-head Git diff (including
  both rename paths and deletions); binds the plan to immutable base/head SHAs,
  resolver/manifest digests and the source inventory digest. It cannot emit native
  qualification success or authorize narrowing.
- `ci-mapping-dry-run.yml`: independent read-only Linux PR job. Candidate is read as
  data only. The resolver and manifest execute from the exact base checkout; if the
  base lacks either, emit a bootstrap/review-required artifact without running the
  candidate resolver. No PR labels or free-text approval affect the plan. Existing
  native workflows do not consume its result.
- PR template: explicit areas, selectors, consumers, plan SHA/artifact and reviewer.

## Local use

Generate the inventory after adding tests:

```
python3 scripts/ci-mapping.py --write-inventory ci/test-inventory.json
```

Emit a local bootstrap plan using full 40-character immutable SHAs:

```
python3 scripts/ci-mapping.py --repo . --manifest ci/test-area-map.json \
  --base BASE_SHA --head HEAD_SHA --bootstrap --output plan.json
```

The output always says DRY_RUN_ONLY, authorizes_narrowing=false, and NOT RUN.
A bootstrap or unsafe plan reports review_required and nonempty conservative native
fallback. Successful plan generation is not a successful mapping review. No worker
is launched and no existing check is skipped. Native source scanning is deliberately
simple; an unsupported Swift Testing declaration or ambiguous source ownership
requires review rather than claiming complete runtime discovery.

## Scope boundary

The complete main execution route, runtime inventory conservation, result aggregation,
branch-protection transitions and final per-area mapping review remain later slices.
No Discussion text or manifest field proves owner approval for those operations.
The current compile/unit/Journal requirements remain in place. Model/real-inference,
backend and device-specific tests retain their separate availability/permission
limits; merely appearing in this inventory does not execute or authorize them.

This slice adds Linux planning work only. No Mac capacity/speed/cost improvement is
claimed until later execution changes are reviewed and measured.
