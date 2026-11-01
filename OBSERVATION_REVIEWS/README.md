# Observation Reviews

This directory records what happened when real people used Ate, how the team interpreted the evidence and what decisions followed.

An observation review is not a telemetry dump, a release report or a list of feature requests. It connects real-world signals to the outcome hypothesis in [PRODUCT_OUTCOMES.md](../PRODUCT_OUTCOMES.md).

## Rules

- Create a review at the end of a defined observation window, and sooner for material safety, privacy, reliability or customer-impacting signals.
- State the cohort, release/build, timeframe and data sources. Include sample size/denominator where available.
- Separate observed facts, interpretation, assumptions and decisions.
- Include qualitative feedback with appropriate privacy handling; do not reproduce unnecessary personal or sensitive content.
- Explain missing data, instrumentation changes, sampling bias and other limitations.
- Do not infer causation or success from raw event volume.
- Record a decision, an owner and a due date, or explicitly state what evidence is still needed.
- Link follow-up issues and update the corresponding outcome register row.
- Preserve history. Add a dated correction rather than rewriting a previously agreed conclusion.

## Observation review template

Copy to a new file named `YYYY-MM-DD-<initiative>-<window>.md`.

```markdown
# Observation Review — <initiative>

- Review date:
- Initiative / outcome issue:
- Outcome register entry:
- Release / build / Git SHA:
- Cohort and eligibility:
- Observation window:
- Review owner:
- Verification record:

## Intended outcome
- Hypothesis:
- Primary measure and pre-agreed decision rule:
- Baseline / target:

## What we observed
| Signal / measure | Definition | Result | Comparison / baseline | Source |
|---|---|---|---|---|

## Qualitative evidence
- Themes:
- Representative feedback (anonymised and minimised):
- Support / beta feedback references:

## Interpretation
- What appears to be working:
- What is not working:
- What surprised us:
- What we cannot conclude:
- Data quality / privacy / sampling limitations:

## Decision
- Continue / Improve / Expand / Roll back / Stop / Gather more evidence:
- Rationale:
- Decision owner and date:

## Actions
| Action / issue | Owner | Due date | Expected learning |
|---|---|---|---|

## Outcome register update
- New status:
- Measure / target changes and rationale:
```

## Cadence

Review new beta feedback and material operational signals weekly during active beta. Produce initiative-level reviews after the observation window defined in its outcome contract. The product owner is accountable for decisions; engineering and support contribute evidence and interpretation.
