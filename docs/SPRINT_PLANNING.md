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

## First sprint — initial proposal (superseded by W45 baseline below)

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


## Retrospective date and time history

Every ticket (issue and PR) has a lifecycle history. Preserve both the raw GitHub event timestamp (UTC ISO-8601) and its Africa/Johannesburg rendering. Do not replace an exact timestamp with a date-only value.

### Required lifecycle fields

| Event | Source of truth | Rule |
|---|---|---|
| Ticket created | GitHub issue/PR `created_at` | Always capture; this is not automatically the actual work start. |
| First recorded activity | Earliest relevant issue/PR event, comment or review | Record event type and actor; do not equate a bot notification with substantive work. |
| Actual work start | Earliest defensible implementation activity (e.g. linked commit, branch activity, or explicit work-start record) | Record timestamp and evidence URL. If evidence is unavailable, mark **Unknown**, not ticket creation date. |
| PR opened | PR `created_at` | Capture exact timestamp, even when issue started earlier. |
| First substantive review | Earliest submitted human review or actionable inline review comment | Exclude automated status/bot summaries. |
| Approval | First qualifying approval that remains valid under repository rules | Preserve later dismissal/re-request events where relevant. |
| Merged | PR `merged_at` | Exact timestamp; only for merged PRs. |
| Issue closed | Issue `closed_at` | Exact timestamp and closure reason where available. |
| Actual completion | Acceptance/closure evidence | Do not assume PR merge means the parent issue's product acceptance is complete. |

### Retrospective reconstruction policy

1. Reconstruct historical events from GitHub metadata, commits, reviews, comments, labels and project history where available.
2. Preserve exact UTC timestamps and show SAST (UTC+02:00) alongside them for reporting.
3. Distinguish **verified**, **inferred**, and **unknown** values. Every inferred value needs its method and evidence link.
4. Never backdate an actual start to issue creation, sprint start, planned start, or PR creation merely because it is convenient.
5. If an exact event cannot be reconstructed, leave it unknown and begin recording it prospectively. Do not fabricate historical timestamps.
6. Keep original planned start/end values immutable. When a commitment moves, append a dated change record with the old dates, new dates, reason, and decision-maker.
7. Calculate lead time (created to completion), implementation time (verified actual start to PR open/merge), review time (PR open to first substantive review/approval), and cycle time (verified actual start to accepted completion) only when both endpoints are known. Report missing/partial samples rather than filling gaps with estimates.
8. Retain the native GitHub lifecycle timestamps even if ticket descriptions or Project fields are later edited.

### Ticket history block

Append a history block to each issue/PR being reconstructed or actively managed:

```md
## Lifecycle history (retrospective)
- Ticket created: YYYY-MM-DDTHH:mm:ssZ (SAST: YYYY-MM-DD HH:mm:ss)
- First recorded activity: <timestamp / event / evidence>
- Actual work start: <timestamp / evidence | Unknown>
- PR opened: <timestamp | N/A>
- First substantive review: <timestamp / evidence | Unknown>
- First qualifying approval: <timestamp / evidence | Unknown>
- Merged: <timestamp | Not merged>
- Issue closed: <timestamp | Still open>
- Confidence: Verified | Inferred | Partial
- Reconstruction notes: <method, gaps and links>
```

### Initial retrospective sample (verified GitHub metadata, 2026-10-30)

The following timestamps are copied from GitHub event metadata. SAST is UTC+02:00. These are ticket-created/opened/review timestamps, **not** inferred actual work-start timestamps.

| Ticket | Event | UTC | SAST |
|---|---|---|---|
| [Issue #30](https://github.com/melusi-k/ate-ios/issues/30) | Created | 2026-10-11 22:50:12Z | 2026-10-12 00:50:12 |
| [Issue #70](https://github.com/melusi-k/ate-ios/issues/70) | Created | 2026-10-13 04:05:22Z | 2026-10-13 06:05:22 |
| [Issue #179](https://github.com/melusi-k/ate-ios/issues/179) | Created | 2026-10-25 01:45:00Z | 2026-10-25 03:45:00 |
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) | Opened | 2026-10-30 17:10:20Z | 2026-10-30 19:10:20 |
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) | First submitted human review (COMMENTED) | 2026-10-30 17:38:28Z | 2026-10-30 19:38:28 |
| [PR #218](https://github.com/melusi-k/ate-ios/pull/218) | Opened | 2026-10-30 20:10:56Z | 2026-10-30 22:10:56 |

**Historical gaps:** actual implementation start for these issues/PRs, first substantive review of PR #218, qualifying approvals, and completion timestamps must be reconstructed from branch/commit/project history where possible. Do not use the PR #218 automated Codex status comment as a human review or approval. PR #206's review is a COMMENTED review, not an approval.


## Sprint 2026-W45 — baseline decision (reviewed 2026-10-30)

**Status:** planned baseline for Monday 2026-11-02 through Sunday 2026-11-08. This review was run before the sprint begins; it is not a retrospective close-out. The Sunday close-out is due 2026-11-08.

**Planning review baseline main:** `ffa8bb6307e1bc4bc8d694bc8305601642f4ea05` (includes the merge of PR #218). Its Build IPA run [41122289453](https://github.com/melusi-k/ate-ios/actions/runs/41122289453) and Dogfood run [41122289262](https://github.com/melusi-k/ate-ios/actions/runs/41122289262) were pending/queued when checked. The current PR #206 head is `02571a4ced4eb2f126aaad345d4b93bfbaa7cad1`; its Compile Check [41120910813](https://github.com/melusi-k/ate-ios/actions/runs/41120910813) and Dogfood Qualification [41120910875](https://github.com/melusi-k/ate-ios/actions/runs/41120910875) were queued/pending, not passing, at review time.

### Committed scope

| Ticket | Commitment | Planned dates | Sprint outcome and acceptance |
|---|---|---|---|
| [Issue #179](https://github.com/melusi-k/ate-ios/issues/179) — Nutrition tracking | Committed — bounded increment only; parent feature issue | 2026-11-02 to 2026-11-08 | Deliver the current PR #206 slice only. Do not claim the entire nutrition initiative is complete. Acceptance is measured by the linked PR #206 criteria; the issue and PR are separate tickets but one implementation outcome for throughput reporting. |
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) — Nutrition foundation | Committed | 2026-11-02 to 2026-11-08 | Fix archive-import atomicity when goals persistence fails; reject non-finite normalized quantities, factors, nutrient values and totals; add failure/overflow regression tests; run Compile Check and Dogfood Qualification on the exact final head; obtain required independent approval and resolve review threads. Merge only if every required gate and repository requirement passes. Empty verified-food catalogue remains an explicit product limitation, not a reason to invent nutrient data. |
| [Issue #30](https://github.com/melusi-k/ate-ios/issues/30) — Release readiness | Committed | 2026-11-02 to 2026-11-08 | Refresh current-main release status; distinguish successful, failed, queued and skipped checks by exact SHA; reconcile share/fallback, sync, device, backend and production-security blockers; attach evidence links and a prioritised next-action plan. Do not mark release ready or close the issue while any required release gate remains open. |

### Stretch scope

| Ticket | Planned dates | Bounded acceptance |
|---|---|---|
| [Issue #70](https://github.com/melusi-k/ate-ios/issues/70) — PRD/checklist/QA ownership reconciliation | 2026-11-05 to 2026-11-08 | Only if committed work is on track: reconcile one concrete, high-risk acceptance ownership/evidence mismatch surfaced by #30, link the exact source/test/run, and record any unresolved ambiguity. Do not attempt to complete the entire coverage-map initiative within this sprint. |

### Explicitly not committed / carryover candidates

- [PR #181](https://github.com/melusi-k/ate-ios/pull/181) remains draft and non-mergeable, with unresolved review findings, no exact-head Compile/Dogfood evidence, no qualifying approval, and an intentionally empty verified-food catalogue. Its nutrition work overlaps the parent #179 and current PR #206; do not count it as a second delivered nutrition outcome. Reconcile/supersede it explicitly before any merge.
- [PR #66](https://github.com/melusi-k/ate-ios/pull/66) remains draft and non-mergeable. Its historic journal UI failures and missing exact-head validation make it unsuitable for a W45 commitment. Physical-device Health/Shortcuts evidence remains separately owned by #67.
- PR #218 is not W45 work: it was merged on 2026-10-30 and delivered this sprint-planning policy/documentation baseline.

### Planning findings and dependencies

- The PRD's implementation-audit header and the MVP checklist progress snapshot are dated 2026-10-24; treat their aggregate status as historical until refreshed from current exact-SHA evidence.
- The live open-issue inventory contains 40 issues; the live open-PR inventory contains 4 PRs (#66, #181, #206, #218 at the time of the query; #218 has since merged). Recent main commits include the insights fallback fix and dependency updates.
- The current release-readiness issue #30 records that release go/no-go remains BLOCKED: the recent Build IPA workflow skips full unit/UI/backend validation, while release acceptance still requires share/fallback, local-library/sync safety, production security and device evidence.
- The repository ruleset `main-production-protection` exists but its enforcement is **disabled**. Its configured rules include one approving review, resolved review threads, strict `compile` and `dogfood-qualification` checks, and linear history. The ruleset also does not require CODEOWNERS approval. The branch-protection endpoint could not be read with the connected GitHub integration (403); do not assume any separate protection is active. No governance setting was changed.
- Repository metadata reports squash merge available, auto-merge unavailable, and update-branch unavailable. Keep the review/validation path manual and evidence-led.
- PR #206 depends on fixing the two review findings, exact-head CI completion, an independent approval and any required base reconciliation. PR #30 depends on current Build IPA, Dogfood, Nightly QA, backend/browser and production-security evidence. #70 depends on a bounded finding from #30.

### Date-change record

- 2026-10-30: PR #206's earlier proposed planned end of **2026-11-06** was superseded by the agreed one-week Monday–Sunday sprint end of **2026-11-08**. The earlier proposal is retained here as history; it is not deleted. The other W45 tickets retain their original planned windows.

### Sprint close-out state

No W44 sprint baseline or committed-versus-delivered record was available to close during this Friday 2026-10-30 run. Therefore no retrospective outcomes or sprint metrics are fabricated. W45 close-out remains due Sunday 2026-11-08 and must report committed versus delivered, carryovers, blockers, scope changes, lessons, next actions, exact evidence and metrics only where both endpoints are evidenced.

## Expanded lifecycle reconstruction — 2026-10-30

All times below are exact UTC ISO-8601 metadata unless marked Inferred; SAST is UTC+02:00. Actual work start is the earliest observable implementation activity, not a claim about when a person first began thinking or working. A human COMMENTED review is not an approval; automated Codex/bot comments are excluded from human-review evidence.

| Ticket | Created/opened (UTC; SAST) | First activity / earliest implementation evidence | Actual work start | First substantive human review | Approval | Merge / closure / completion |
|---|---|---|---|---|---|---|
| [Issue #30](https://github.com/melusi-k/ate-ios/issues/30) | 2026-10-11T22:50:12Z; 2026-10-12 00:50:12 | First recorded event: `labeled` at 2026-10-11T22:50:13Z; 2026-10-12 00:50:13 (Verified) | Unknown | No single issue-level review event; linked PR reviews are tracked on their own tickets | N/A — issue | Still open; no completion |
| [Issue #70](https://github.com/melusi-k/ate-ios/issues/70) | 2026-10-13T04:05:22Z; 2026-10-13 06:05:22 | Earliest returned event: `labeled` at 2026-10-21T10:37:09Z; 2026-10-21 12:37:09 (Verified) | Unknown | No single issue-level review event | N/A — issue | Still open; no completion |
| [Issue #179](https://github.com/melusi-k/ate-ios/issues/179) | 2026-10-25T01:45:00Z; 2026-10-25 03:45:00 | First returned issue event: commit `referenced` at 2026-10-25T21:27:10Z; 2026-10-25 23:27:10 (Verified). Earlier linked implementation commit is recorded below. | 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 (Inferred from earliest commit in linked PR #181; not the issue creation time) | No issue-level review; see PR #181 and #206 | N/A — issue | Still open; no completion |
| [PR #66](https://github.com/melusi-k/ate-ios/pull/66) | 2026-10-12T23:14:40Z; 2026-10-13 01:14:40 | Earliest branch commit `6ada6530` at 2026-10-12T23:13:39Z; 2026-10-13 01:13:39 (Verified) | 2026-10-12T23:13:39Z; 2026-10-13 01:13:39 (Inferred earliest observable implementation activity) | 2026-10-13T03:39:11Z; 2026-10-13 05:39:11 (Verified, human COMMENTED review by PR author) | None verified | Open, draft, non-mergeable; not completed |
| [PR #181](https://github.com/melusi-k/ate-ios/pull/181) | 2026-10-25T06:44:01Z; 2026-10-25 08:44:01 | Earliest branch commit `d3a141de` at 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 (Verified) | 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 (Inferred earliest observable implementation activity) | 2026-10-30T05:02:18Z; 2026-10-30 07:02:18 (Verified, substantive human COMMENTED review by PR author; no approval) | None verified | Open, draft, non-mergeable; not completed |
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) | 2026-10-30T17:10:20Z; 2026-10-30 19:10:20 | Earliest branch commit `02571a4c` at 2026-10-30T20:08:27Z; 2026-10-30 22:08:27 (Verified) | 2026-10-30T20:08:27Z; 2026-10-30 22:08:27 (Inferred earliest observable implementation activity) | 2026-10-30T17:38:28Z; 2026-10-30 19:38:28 (Verified, human COMMENTED self-review; not independent approval) | None verified | Open, ready-for-review, mergeable flag true; exact-head Compile and Dogfood were queued, not passed |
| [PR #218](https://github.com/melusi-k/ate-ios/pull/218) | 2026-10-30T20:10:56Z; 2026-10-30 22:10:56 | First branch commit `343128f3` at 2026-10-30T20:10:28Z; 2026-10-30 22:10:28 (Verified) | 2026-10-30T20:10:28Z; 2026-10-30 22:10:28 (Inferred earliest observable implementation activity) | None verified; no human review submission found | None verified | Merged and closed 2026-10-30T20:19:48Z; 2026-10-30 22:19:48; docs delivery complete at merge commit `ffa8bb6307e1bc4bc8d694bc8305601642f4ea05` |

### Evidence-based timing metrics (available samples only)

- PR #218 lead time (created to merged): **8m 52s** (Verified endpoints).
- PR #218 implementation time is not reported: the first commit is an inferred earliest observable start, not a verified actual start.
- PR #66 time to first substantive human review: **4h 24m 31s** (Verified timestamps; review was a COMMENTED self-review, not approval).
- PR #181 time to first substantive human review: **4d 22h 18m 17s** (Verified timestamps; COMMENTED self-review, not approval).
- PR #206 time to first substantive human review: **28m 08s** (Verified timestamps; COMMENTED self-review, not approval).
- No qualifying approval time, PR #66/#181/#206 completion time, or issue #30/#70/#179 cycle time is available. Lead/implementation/cycle metrics for open tickets are therefore not calculated.


### Post-update validation state (2026-10-30)
The sprint-planning documentation update is on current `main` at `85fb3a3b9bce2403d70ca1696c71b6a7cc474e73`. Build IPA [41122745563](https://github.com/melusi-k/ate-ios/actions/runs/41122745563) and Dogfood Qualification [41122745893](https://github.com/melusi-k/ate-ios/actions/runs/41122745893) were queued when last polled. No pass is claimed until these exact-SHA runs complete. The latest completed Release Readiness run [41120466099](https://github.com/melusi-k/ate-ios/actions/runs/41120466099) succeeded on the older SHA `ff49fcb6326fc96b9126c72824a1670eca878758`; it is not current-main validation. The generated readiness issue snapshot sourced from run [41120191792](https://github.com/melusi-k/ate-ios/actions/runs/41120191792) is not current evidence because that Build IPA run was cancelled on `0529e37f56625bb97eb39fb125064e54d802185a`.


### CI refresh — 2026-10-30T20:24Z (UTC) / 2026-10-30 22:24 SAST

The main branch advanced after the initial baseline capture. Current main is now `764de191449704359a5dbdc8cb9fb18b737de50f` (commit message: `docs: record current-main validation state for sprint baseline`). On this exact SHA:
- Release readiness run [41122835651](https://github.com/melusi-k/ate-ios/actions/runs/41122835651): queued.
- Release readiness run [41122833951](https://github.com/melusi-k/ate-ios/actions/runs/41122833951): queued.
- Dogfood Qualification [41122795770](https://github.com/melusi-k/ate-ios/actions/runs/41122795770): queued.
- Build IPA [41122795709](https://github.com/melusi-k/ate-ios/actions/runs/41122795709): queued.
- Supabase Preview check: completed **failure** at 2026-10-30T20:23:38Z.
- Therefore main is not release-cleared; pending jobs are not passes and the Supabase Preview failure remains a blocker to investigate.

PR #206 exact head remains `02571a4ced4eb2f126aaad345d4b93bfbaa7cad1`. Its Compile [41120910813](https://github.com/melusi-k/ate-ios/actions/runs/41120910813) and Dogfood Qualification [41120910875](https://github.com/melusi-k/ate-ios/actions/runs/41120910875) are queued, not passing. A subsequent label-automation check is also queued; it is not a product validation gate.


## Guardian refresh — 2026-10-31 (W45 pre-start evidence)

**Evidence cutoff:** 2026-10-31T06:53:48Z / 2026-10-31 08:53:48 Africa/Johannesburg. This is a status refresh, not a Monday planning event or Sunday retrospective.

### Current main and release evidence
- Current main: `cd8d7f9b3db2b3e17a74816c5f1579d99401cf6b`, merged from PR #230 at 2026-10-31T06:39:50Z / 08:39:50 SAST.
- Build IPA [41177530921](https://github.com/melusi-k/ate-ios/actions/runs/41177530921) is in progress, but unit tests, focused regressions, KeyFlows QA, Tracker/Cook Mode, header regressions, signed IPA build and final full-validation enforcement were skipped; UI-suite and backend-E2E were skipped. This is not a current-main full-validation pass.
- Supabase Preview failed on the same main SHA: [check run 124468258482](https://github.com/melusi-k/ate-ios/runs/124468258482). Retain as a blocker pending diagnosis and a fresh successful check.
- PRs #204, #221, #222 and #223 have merged, but issue #195 remains open and its remaining acceptance work and current-main validation must not be assumed complete from merge status alone.

### W45 dependency and PR refresh
- The W45 committed baseline remains [issue #179](https://github.com/melusi-k/ate-ios/issues/179) + [PR #206](https://github.com/melusi-k/ate-ios/pull/206) for one bounded nutrition-foundation outcome, plus [issue #30](https://github.com/melusi-k/ate-ios/issues/30) for release-readiness evidence. [Issue #70](https://github.com/melusi-k/ate-ios/issues/70) remains Stretch only. Preserve the existing planned windows and the earlier #206 2026-11-06 proposal as historical; the agreed W45 end remains 2026-11-08.
- **Scope/dependency change recorded 2026-10-31:** [PR #231](https://github.com/melusi-k/ate-ios/pull/231) was added as the stacked child (position 2/2) of root [PR #206](https://github.com/melusi-k/ate-ios/pull/206), to address safe backup-before-reset for corrupt nutrition goals. It inherits the 2026-11-02 to 2026-11-08 W45 window as a dependency, not a separate delivery or throughput outcome. Merge root #206 first; after it merges, retarget/reconcile #231 to main, inspect the incremental diff and rerun all required exact-head checks.
- PR #206 head `0bb70c22d0e19f6079d2224ee6fbc3366850993a` is 7 ahead / 17 behind current main. Dogfood [41175981615](https://github.com/melusi-k/ate-ios/actions/runs/41175981615) passed; Compile [41175981579](https://github.com/melusi-k/ate-ios/actions/runs/41175981579) is still in progress with focused regression failures in #83 and #145 and Cook Mode tests still running. No independent approval is recorded.
- PR #231 head `e3a4944bc353404005cb7ee249fab8bfd8f4261b` is 9 commits ahead of its parent branch; Compile [41178109316](https://github.com/melusi-k/ate-ios/actions/runs/41178109316) is queued and Dogfood [41178109351](https://github.com/melusi-k/ate-ios/actions/runs/41178109351) is in progress. It remains draft and unapproved.
- PR #181 remains draft, dirty, 21 ahead / 240 behind, with three unresolved review threads and no exact-head Compile/Dogfood evidence; its overlapping nutrition implementation is not a second committed outcome. PR #66 remains draft, dirty, 38 ahead / 592 behind, with no exact-head Compile/Dogfood evidence; device acceptance remains separate in #67.

### Governance refresh
- Ruleset [main-production-protection](https://github.com/melusi-k/ate-ios/rules/26236404) exists but `enforcement=disabled`. It is configured for one approving review, resolved review threads, strict `compile` and `dogfood-qualification` checks, linear history and no bypass actors.
- `.github/CODEOWNERS` exists with `* @melusi-k`, but the ruleset has `require_code_owner_review=false`; a CODEOWNERS approval is not enforced by this ruleset.
- The branch-protection endpoint remains inaccessible to the connected integration (403), so any separate protection is unverified. Repository metadata: squash merge enabled, auto-merge disabled, update-branch disabled.
- Do not auto-merge until enforcement is enabled and the required checks/review/ownership rules are verified. No repository governance setting was changed by this refresh.

### Retrospective timing note
- 2026-W44 closes Sunday 2026-11-01. No W44 committed baseline was present in the records reviewed, so the Sunday close-out must state that commitment accuracy/carryover denominators are unavailable; do not reconstruct a fictitious commitment or infer actual starts from ticket creation or sprint dates.
- W45 remains planned for Monday 2026-11-02 through Sunday 2026-11-08. Monday planning should revalidate main, PR #206/#231 exact-head CI, review status, issue #30 release blockers and the current backlog before confirming the commitment. Sunday close-out is due 2026-11-08.
