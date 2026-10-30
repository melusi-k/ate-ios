# Weekly sprint planning and delivery

**Cadence:** one calendar week, Monday through Sunday.  
**Timezone:** Africa/Johannesburg (SAST, UTC+02:00).  
**Planning baseline:** 2026-10-30.  
**First proposed sprint:** 2026-11-02 through 2026-11-08.

## Purpose and sources of truth

Every sprint is a small, evidence-led commitment against the current product and engineering state. Planning reviews must inspect:

1. The current `main` codebase and latest commit.
2. `docs/PRD.md` for intended product outcomes and constraints.
3. `docs/PRODUCT_BACKLOG.md` and `docs/PRD_GAP_REGISTER.md` for ownership and priority.
4. `docs/MVP_CHECKLIST.md` and `docs/QA_MATRIX.md` for acceptance IDs and verification evidence.
5. Open issues, pull requests, review threads, CI runs, release readiness and external dependencies.

The issue remains the owner of its implementation checklist and acceptance criteria. The PRD/checklist/matrix remain the product and verification sources of truth. Sprint planning does not convert an implementation claim into acceptance evidence.

## Ticket scheduling contract

Add this block to every issue or PR selected for a sprint:

```md
## Sprint schedule
- Sprint: YYYY-Www — <sprint name>
- Planned start: YYYY-MM-DD
- Planned end: YYYY-MM-DD
- Actual start: YYYY-MM-DD (leave blank until work begins)
- Actual end: YYYY-MM-DD (leave blank until accepted)
- Commitment: Committed | Stretch | Carryover
- Sprint outcome: <one measurable outcome>
- Dependencies/blockers: <links or None>
```

Rules:

- Planned dates are the agreed forecast, not a promise that overrides evidence or new blockers.
- Actual dates are recorded separately and never inferred from planned dates.
- The planned end date is the target for completion/acceptance, not merely code completion.
- A ticket spanning multiple sprints must be split into independently acceptable deliverables where practical. Otherwise, record it as carryover and explain the remaining scope.
- Do not assign dates to closed/done work retrospectively unless reliable historical dates exist.
- Do not change priority or release-gate labels just to fit a sprint.
- Pull requests inherit the schedule of their owning issue; a PR can have its own schedule only when it represents a separately planned deliverable.
- Keep the weekly commitment small enough to leave capacity for review, CI failures, regressions and release blockers.

## Weekly operating rhythm

| Day | Activity | Required output |
|---|---|---|
| Monday | Sprint planning and commitment | Reviewed backlog, sprint goal, dated tickets, dependencies and capacity |
| Tuesday–Thursday | Delivery and continuous review | Updated issue status, PR links, review notes and CI evidence |
| Friday | Validation and risk review | Exact-SHA test/CI evidence, acceptance status, blocker decisions |
| Sunday | Sprint close and next-sprint preparation | Completed/carryover list, actual dates, outcome and next candidate backlog |

A sprint closes on Sunday even if a ticket remains open. Incomplete work is not marked done; it is explicitly carried over or returned to the backlog.

## Planning and commitment rules

1. Start with release-blocking, data-integrity, security, reliability and user-facing defects.
2. Check whether a task is already delivered on `main`, superseded, duplicated, blocked by an external dependency, or represented by an active PR.
3. Read the relevant code and tests before estimating or committing.
4. Select a small set of outcomes that can be independently accepted within the week.
5. Each commitment must have an owner, acceptance criteria, verification method, dependencies and planned dates.
6. Keep Stretch work separate from Committed work. Do not silently turn stretch into a promise.
7. On Friday/Sunday, compare planned and actual outcomes and record why dates moved.
8. Never weaken a test gate or claim a pass to protect a sprint commitment.

## First sprint — proposed, not yet baselined

**Sprint:** 2026-W45  
**Dates:** 2026-11-02 to 2026-11-08  
**Sprint goal:** improve release confidence while completing the active nutrition foundation safely.

| Candidate | Proposed outcome | Planned window | Commitment |
|---|---|---|---|
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) / [issue #179](https://github.com/melusi-k/ate-ios/issues/179) | Resolve review findings, validate archive-import atomicity and nutrition arithmetic, then obtain exact-head required CI evidence. Merge only if every required gate passes and review requirements are met. | 2026-11-02–2026-11-06 | Committed candidate |
| [Issue #30](https://github.com/melusi-k/ate-ios/issues/30) | Refresh release-readiness status against current `main`; identify the highest-impact remaining share/fallback, sync and CI risks; attach current evidence and recommend the next release-blocker work. | 2026-11-02–2026-11-08 | Committed candidate |
| [Issue #70](https://github.com/melusi-k/ate-ios/issues/70) | Reconcile the next highest-risk PRD acceptance gaps only where Sprint 1 release review exposes an ownership/evidence ambiguity. | 2026-11-05–2026-11-08 | Stretch |

This is an initial planning proposal based on the repository snapshot reviewed on 2026-10-30. Monday planning must re-check current `main`, open PR heads, CI status, review threads and the latest PRD/checklist evidence before converting candidates to firm commitments. If PR #206 is blocked by unresolved review findings or failing required checks, do not merge it to meet the sprint date; re-scope or carry it over.

## Sprint close report template

- Sprint:
- Goal:
- Committed tickets completed:
- Committed tickets not completed:
- Stretch completed:
- Actual start/end dates:
- Acceptance evidence (exact commit, workflow run, tests, device/browser evidence):
- Carryovers and reasons:
- Scope changes:
- Risks/dependencies:
- Recommended next sprint goal:
