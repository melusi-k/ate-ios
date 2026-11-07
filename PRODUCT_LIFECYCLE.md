# Ate Product Lifecycle Framework

> Governing contract for turning customer problems into measurable, verified and continuously improved product outcomes.

## Principle

A feature is not complete merely because it has been implemented, merged or released. It is complete when we have demonstrated that it works as intended and understood whether it delivered the outcome we set out to achieve.

Engineering maturity and product maturity are related, but they are not interchangeable. Passing CI proves only what the executed checks cover. A release proves availability, not customer value. Product completion requires evidence across all four stages below.

## The lifecycle

Every meaningful product initiative moves through four connected stages. The stages are iterative: observation can reopen planning, verification can send work back to build, and planning can revise an outcome when evidence changes our understanding.

| Stage | Purpose | Human judgment | Required artifact |
|---|---|---|---|
| Plan | Define and measure goals | Choose the right problem, resolve ambiguity and make trade-offs | Outcome contract in the issue and an entry in [PRODUCT_OUTCOMES.md](PRODUCT_OUTCOMES.md) |
| Build | Translate goals into a working system | Guide design choices and resolve decisions requiring product/engineering judgment | Candidate implementation PR, decision context and test coverage |
| Verify | Establish whether the candidate meets its contract and is safe to release | Judge acceptance evidence, limitations and release risk | Exact-candidate Verification Record in [VERIFICATION_RECORDS/](VERIFICATION_RECORDS/) |
| Observe | Operate the product and interpret real outcomes | Interpret signals, identify insights and decide what changes or ships | Observation Review in [OBSERVATION_REVIEWS/](OBSERVATION_REVIEWS/) |

## Stage definitions and exit criteria

### 1. Plan

Start with a customer problem, not a predetermined solution.

A meaningful initiative must state:
- Target user, context and job-to-be-done (JTBD).
- Problem and supporting evidence; distinguish facts from assumptions.
- Desired customer outcome and why it matters.
- Baseline, success measure, observation window and intended cohort where measurable.
- Functional acceptance criteria and important non-functional constraints.
- Verification approach and observation plan.
- Scope, trade-offs, dependencies, risks and release commitment.

**Exit:** The owner and relevant product/engineering stakeholders agree that the problem, outcome, measures and acceptance criteria are sufficiently clear to build. Small maintenance work may use a proportionate issue template, but must still state its purpose and how it will be checked.

### 2. Build

The implementation should preserve traceability to the agreed outcome.

The PR must explain:
- What changed and which issue/outcome it serves.
- Important design decisions and alternatives rejected where relevant.
- Data, privacy, security, accessibility and migration implications.
- Tests added/changed and what they do not cover.
- Rollout, feature-flag, backend and operational requirements.
- Known limitations and follow-up work.

**Exit:** The candidate is reviewable, linked to its issue, has appropriate tests, and is ready for exact-candidate verification. A merge is not proof of product success.

### 3. Verify

Verification asks whether this specific candidate satisfies its contract under recorded conditions.

Evidence must identify the exact commit SHA, build number, release channel, environment, device/OS where relevant, executed checks, results, artifacts and human decisions. A result from another SHA or build is historical context, not a pass for the candidate.

Use the existing [QA acceptance matrix](docs/QA_MATRIX.md), release-readiness scripts and CI workflows as evidence sources; do not create a parallel test inventory. Distinguish Pass, Failed, Blocked, Not run, Skipped and Partial. Missing evidence is never a pass. Quarantined tests remain visible and cannot silently improve a candidate's result.

**Exit:** A human release owner reviews the candidate's evidence and explicitly records the decision: eligible, not eligible, or conditionally eligible with named restrictions. Only eligible candidates may proceed under the repository's release policy. This framework does not override existing launch gates.

### 4. Observe

Observation begins when a candidate reaches its intended users and continues throughout operation.

Review:
- Adoption and journey completion against the defined baseline.
- Reliability, errors and performance.
- Qualitative feedback, support reports and usability findings.
- Cohort, version and release context.
- Data quality, missing signals and limitations.
- Unintended consequences and privacy implications.

Every review records what was observed, what can and cannot be inferred, the decision, owner and follow-up. Outcomes may be positive, negative, mixed or inconclusive. Do not invent targets after seeing results or equate activity volume with customer value.

**Exit:** The observation has a recorded interpretation and decision: continue, improve, roll back, expand, stop, or gather more evidence. Resulting work links back to a new or updated Plan issue.

## Roles and accountability

One person may hold multiple roles in a small team, but accountability must be explicit for each initiative.

- **Product owner:** accountable for problem framing, outcome measures, prioritisation, acceptance intent and product decisions.
- **Engineering owner:** accountable for implementation quality, technical trade-offs, tests, operational readiness and accurate engineering evidence.
- **Verification/release owner:** accountable for reviewing candidate-specific evidence and recording the release decision. This role must not infer success from a green workflow summary alone.
- **Observation owner:** accountable for reviewing available signals, documenting interpretation and proposing follow-up. Product owner remains accountable for resulting product decisions.

Human judgment is required at each stage. Automation may gather evidence and enforce invariants; it must not fabricate intent, decide customer value or silently approve release.

## Traceability contract

For each significant initiative, preserve this chain:

`Outcome/Issue → PR(s) → commit SHA → build → verification record → release → observation review → follow-up issue/outcome`

Use canonical GitHub issue, PR, commit, workflow, build and artifact links. Where a stage has not happened, record its status rather than creating placeholder evidence. Stacked PRs remain linked to the same initiative and must not be mistaken for separate product outcomes.

## Source-of-truth boundaries

This framework connects existing sources; it does not duplicate them.

- [PRODUCT_OUTCOMES.md](PRODUCT_OUTCOMES.md): outcome register, measures and status.
- [docs/PRD.md](docs/PRD.md), [docs/MVP_CHECKLIST.md](docs/MVP_CHECKLIST.md): product requirements and acceptance inventory.
- [docs/QA_MATRIX.md](docs/QA_MATRIX.md), [docs/LAUNCH_GATES.md](docs/LAUNCH_GATES.md): test definitions and release policy.
- [docs/TELEMETRY.md](docs/TELEMETRY.md), [docs/BETA_FEEDBACK.md](docs/BETA_FEEDBACK.md): privacy and collection contracts.
- `.github/ISSUE_TEMPLATE/product_outcome.yml`: Plan-stage issue capture.
- `.github/pull_request_template.md`: Build-stage implementation and evidence context.
- [VERIFICATION_RECORDS/](VERIFICATION_RECORDS/): candidate-specific evidence snapshots.
- [OBSERVATION_REVIEWS/](OBSERVATION_REVIEWS/): interpreted product outcomes and decisions.

## Governance and quality rules

1. No outcome without an owner and a clear problem statement.
2. No significant feature without measurable intended outcomes or an explicit reason measurement is not appropriate.
3. No verification pass without evidence for the exact candidate.
4. No release decision inferred solely from merge status or aggregate workflow conclusion.
5. No observation claim without cohort, timeframe, source and limitations where applicable.
6. No telemetry expansion without privacy review and alignment with the telemetry contract.
7. No product-learning review without a recorded decision or an explicit statement that more evidence is needed.
8. Preserve historical records. Correct mistakes with a dated addendum; do not rewrite a previously issued verification or observation record to make history appear different.
9. Keep governance proportional: use the full contract for meaningful customer-facing initiatives and a concise path for small fixes.
10. Revisit outcomes when evidence invalidates the original assumptions.

## Adoption

This framework becomes active when merged. Existing work is not retroactively declared compliant. Open initiatives should be brought into the framework when they next receive substantive changes or approach release. The initial adoption review should identify owners, baseline gaps and candidate evidence gaps without inventing missing historical data.
