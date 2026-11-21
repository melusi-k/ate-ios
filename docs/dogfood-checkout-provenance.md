# Dogfood checkout provenance and cache trust boundary

## Alert

PR638 head86288b7c6c0c1a7dc319930ba9b3deba79a7c0aa, CodeQL check136916599935 reports11 high cache-poisoning paths in dogfood-qualification.yml. Each starts from checkout ref needs.pin-source.outputs.sha in workflow_dispatch context and reaches build/install/artifact work. The11 annotations identify lines48,82,102,150,177,211,231,285,310,344,406.

- https://github.com/melusi-k/ate-ios/runs/136916599935
- https://api.github.com/repos/melusi-k/ate-ios/check-runs/136916599935/annotations

The current pin-source job computes that output from the immutable event PR head or run SHA, validates40hex and emits it. It has no dispatch input and does not run candidate code. Nevertheless using a general job output as the checkout authority obscures origin from security analysis and makes future changes to the producer capable of redirecting execution under the dispatch ref's cache authority. A hexadecimal check alone validates shape, not trusted source.

## Narrow correction

Change ONLY the four native/aggregate checkout refs to the direct immutable event expression already used to compute the pin: github.event.pull_request.head.sha || github.sha. No change to pin-source computation, receipt expected-source values, source equality verification, caches, artifact steps, permissions, native commands, selected cases, assertions, budgets, or strict same-source AND gate.

For pull_request the checkout remains the event's frozen head, not the merge ref. For workflow_dispatch no PR object exists, so checkout can only select github.sha of the run itself, not a cross-job output or arbitrary input. The native pre-execution receipt verification still checks actual git HEAD against frozen pin-source output. Tampering or mismatching that output now cannot redirect checkout and is rejected before native/cache steps. Lane receipts remain after native verification/upload, and the aggregate still requires both successful exact-source lane receipts. No success shortcut or suppression is added.

The4-line source correction restores explicit event provenance to the checkout trust boundary, rather than muting the security alert. It does not claim that the original fixed producer was exploited or that cache poisoning occurred. It also does not claim CodeQL acceptance before the new exact-head check actually runs.

## Verification

469 Python tests pass11.030s, including exact four-ref whole-workflow inverse and missing/duplicate/unrelated mutants, event/pin equality, receipt mismatch refusal, native-command subprocess failures, all original12cases/caps, and strict AND wrong-source/cancel checks. Older frozen split hashes/fixtures unchanged; the new exact inverse normalizes only these four refs before historical guards.

Workflow YAML and all shell bodies are covered by existing passing tests. Diff-check clean. App source, native test sources, case ledger, gate helper and receipt helper unchanged. No native rerun, manual dispatch, alert dismissal, CodeQL exclusion, bypass or merge performed. Reviewer independently reviews then publishes this ordinary descendant source onto the existing638 branch. New exact-head CodeQL and normal gates remain required.
