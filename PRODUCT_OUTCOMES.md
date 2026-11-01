# Ate Product Outcomes

> Register of the customer outcomes Ate intends to create and the evidence used to judge them. This is not a feature inventory or a release checklist.

The governing process is [PRODUCT_LIFECYCLE.md](PRODUCT_LIFECYCLE.md). Detailed requirements remain in the PRD and acceptance inventory; test definitions remain in the QA matrix.

## Measurement principles

- Start with the customer job and intended change, not an arbitrary metric.
- Record a baseline before setting a target. If no baseline exists, the first action is to establish one.
- Define cohort, denominator, timeframe, event semantics and data source before interpreting a rate.
- Separate leading indicators (e.g. journey starts) from outcomes (e.g. successful completion, repeat value).
- Use qualitative feedback alongside quantitative signals.
- Treat missing or low-quality data as unknown, not zero.
- Do not collect sensitive content or identifiers merely to improve measurement. Follow [docs/TELEMETRY.md](docs/TELEMETRY.md) and [docs/BETA_FEEDBACK.md](docs/BETA_FEEDBACK.md).
- Do not claim causation from simple before/after comparisons without a defensible evaluation design.

## Outcome contract template

Copy this into the relevant GitHub issue and link the issue below.

### Problem and JTBD
- Target user/context:
- When I...:
- I want to...:
- So that...:
- Evidence / assumptions:

### Intended outcome
- Customer change we expect:
- Why it matters:
- Owner:
- Initiative / issue:

### Measurement plan
- Primary outcome measure:
- Definition / numerator / denominator:
- Baseline and baseline period:
- Target and rationale (or "baseline to be established"):
- Cohort / segmentation:
- Observation window:
- Data source and event definitions:
- Known blind spots / privacy constraints:

### Delivery and verification
- Acceptance criteria:
- Verification approach:
- Release gate:
- Dependencies / risks:

### Decision rule
- What evidence would mean success?
- What would trigger iteration, rollback or stopping?
- Who makes the decision and when?

## Outcome register

Status values: **Proposed**, **Baseline needed**, **In progress**, **Ready to observe**, **Observing**, **Decision recorded**, **Superseded**. A status describes lifecycle state, not a success score.

| Outcome / initiative | Customer outcome hypothesis | Primary measure | Baseline / target | Owner | Status / source |
|---|---|---|---|---|---|
| Unified Food Journal ([#245](https://github.com/melusi-k/ate-ios/issues/245)) | People can capture meals and reflections in one coherent timeline and find it useful enough to return to. | Repeat journal use within a defined cohort and observation window; supporting measures: entry completion and reflection/recipe association rates. | Baseline needed; establish before setting a target. | Product owner to confirm | In progress |
| Nutrition tracking ([#179](https://github.com/melusi-k/ate-ios/issues/179)) | People can understand and maintain a useful record of their food and nutrition. | Successful diary-entry completion and repeat usage; assess quality and user-reported usefulness. | Baseline needed; do not infer nutrition accuracy from entry volume. | Product owner to confirm | In progress |
| Recipe creation and AI quality | People can create trustworthy, usable recipes with less effort and understand when AI output needs correction. | Validated generation completion, correction/abandonment signals and structured quality evaluation. | Baseline needed; separate mock tests from real-model and user outcomes. | Product owner to confirm | In progress |
| Cooking experience | People can confidently cook a saved recipe and complete the intended cooking journey. | Cook-mode completion relative to starts, with reliability and qualitative feedback. | Baseline needed. | Product owner to confirm | Proposed |
| Beta feedback loop | Testers can report useful feedback and the team can triage it into decisions. | Feedback triage time, disposition rate and linked follow-up decisions; submission volume is contextual only. | Establish operational baseline after consistent triage begins. | Product owner to confirm | Ready to observe |

This initial register is deliberately conservative. It records hypotheses and baseline gaps, not fabricated targets or claims that the outcomes have already been achieved.

## Review cadence

- **Weekly during active beta:** review new feedback, reliability signals and urgent journey issues.
- **At each candidate/release:** confirm which outcome measures can be observed for that build and cohort.
- **After the agreed observation window:** create an Observation Review with the result, limitations and decision.
- **Quarterly or at major product shifts:** revisit outcome definitions, relevance and privacy.

Every row should link to the relevant issue, PR, verification record and observation review as those artifacts become available.
