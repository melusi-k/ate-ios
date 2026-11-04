---
name: ate-release-readiness
description: Use when preparing or reviewing Ate pull requests, CI evidence, release gates, rollout plans, or feature acceptance.
---

# Ate release readiness

## Scope and status

Keep implementation, build success, automated tests, simulator verification, device acceptance, and release approval as separate states. Never claim a feature is complete based on a single passing check.

## Pull request discipline

- Read the repository PR template and stacked-PR guidance.
- Keep each PR focused and reviewable; declare stack metadata exactly as required.
- Describe user impact, scope, risks, migration/rollout, and rollback considerations.
- Link the owning issue and state whether this PR alone satisfies its acceptance criteria.
- Include exact test commands, CI run identifiers, and evidence; distinguish pending checks from completed checks.
- Do not bypass, weaken, quarantine, or silently skip required checks.

## Rollout planning

For user-facing or data-affecting changes, document prerequisites, feature flags or staged exposure where applicable, monitoring, support signals, rollback/disable strategy, and data compatibility. Do not invent rollout controls that the implementation does not provide.

## Acceptance checklist

- Scope matches the approved work.
- Relevant targets build.
- Required unit, integration, and UI checks pass on the proposed head.
- Manual simulator/device checks are recorded where required.
- Accessibility, privacy, data integrity, and migration risks are considered.
- Open risks and follow-up work are explicit.
- Release owner has the evidence needed to make the acceptance decision.
