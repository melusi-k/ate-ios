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
- `.github/CODEOWNERS` exists with `* @melusi-k`, but the ruleset has `require_code_owner_review=false`; a CODEOWNERS approval is not enforced by this ruleset. The file says owner review should be required, but its only listed owner is the repository author; nominate an independent maintainer/team before enabling that requirement. Never self-approve.
- The branch-protection endpoint remains inaccessible to the connected integration (403), so any separate protection is unverified. Repository metadata: squash merge enabled, auto-merge disabled, update-branch disabled.
- Do not auto-merge until enforcement is enabled and the required checks/review/ownership rules are verified. No repository governance setting was changed by this refresh.

### Retrospective timing note
- 2026-W44 closes Sunday 2026-11-01. No W44 committed baseline was present in the records reviewed, so the Sunday close-out must state that commitment accuracy/carryover denominators are unavailable; do not reconstruct a fictitious commitment or infer actual starts from ticket creation or sprint dates.
- W45 remains planned for Monday 2026-11-02 through Sunday 2026-11-08. Monday planning should revalidate main, PR #206/#231 exact-head CI, review status, issue #30 release blockers and the current backlog before confirming the commitment. Sunday close-out is due 2026-11-08.


## Guardian refresh — 2026-10-31T09:05:44Z (UTC) / 2026-10-31 11:05:44 Africa/Johannesburg

**Evidence cutoff:** 2026-10-31T09:05:44Z. This is a Saturday pre-sprint status refresh, not a Monday planning event or Sunday retrospective. No planned dates were changed.

### Sprint schedule and commitment status

- **2026-W44:** closes Sunday 2026-11-01. No W44 committed baseline was found in the reviewed records. Sunday retrospective must report commitment accuracy and carryover rate as unavailable; do not invent a denominator.
- **2026-W45:** Monday 2026-11-02 through Sunday 2026-11-08. Existing baseline remains unchanged:
  - **Committed:** issue #30 (release-readiness evidence refresh); issue #179 + root PR #206 (one bounded nutrition-foundation delivery outcome).
  - **Dependent child:** PR #231 inherits the #179/#206 window and acceptance dependency; do not count it as a second delivery.
  - **Stretch:** issue #70, limited to one evidence-backed ownership/QA mismatch if committed work is on track.
  - **Carryover candidates:** PR #181 (older overlapping nutrition work) and PR #66 (journal acceptance coverage). Neither is a W45 commitment and neither receives new dates.
  - **Not scheduled:** PR #234 (QA scope reclassification). It changes release acceptance policy and must be reviewed/approved separately before being considered for a sprint.
- Original planned dates are preserved. The earlier #206 proposal ending 2026-11-06 remains historical; the agreed Monday–Sunday window ends 2026-11-08.

### Current main and release readiness

- Current `main`: `7a84441651da07e08cfe398a72588d89af9888cd`; PR #233 merged at 2026-10-31T08:09:24Z / 10:09:24 SAST.
- Current release-readiness snapshot [run 41183432551](https://github.com/melusi-k/ate-ios/actions/runs/41183432551) on that SHA is **BLOCKED**: 1/59 verified, 12 failing, 46 open. Unit, QA 8-flow, UI and backend-E2E jobs were skipped; QA-results retrieval failed with HTTP 400. A successful workflow wrapper or artifact does not override skipped inner validation.
- The main-branch QA matrix remains authoritative until PR #234 is explicitly approved and merged. Its proposed A-SHARE-05 N/A and A-WIDGET-05 Pass changes are not current-main acceptance evidence.

### Open PR status at evidence cutoff

| PR | Sprint classification | Branch / exact-head evidence | Decision |
|---|---|---|---|
| [#206](https://github.com/melusi-k/ate-ios/pull/206) | W45 committed root for #179 | Head `75da84cc955cbeefe58b28b888a3fb3cc786b093`, 12 ahead / 0 behind main. Dogfood passed [41185965394](https://github.com/melusi-k/ate-ios/actions/runs/41185965394); Compile [41185965539](https://github.com/melusi-k/ate-ios/actions/runs/41185965539) still in progress. | Blocked: no independent approval; current code still treats corrupt diary bytes as empty (possible overwrite) and daily-total rounding can overflow at `sum * 10`. |
| [#231](https://github.com/melusi-k/ate-ios/pull/231) | Dependent child of committed #206; not separately counted | Head `e3a4944bc353404005cb7ee249fab8bfd8f4261b`, based on old #206 head `0bb70c22d0e19f6079d2224ee6fbc3366850993a`. Dogfood passed [41178109351](https://github.com/melusi-k/ate-ios/actions/runs/41178109351); Compile failed [41178109316](https://github.com/melusi-k/ate-ios/actions/runs/41178109316) at #83 and #145. | Draft. Root must merge first; then reconcile child to main and rerun exact-head checks. |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | Not selected for W45; no dates | Head `ae637f5a6593705f6e8cbc5c58ac2b3e5b099862`, 22 ahead / 3 behind main. Dogfood passed [41184200200](https://github.com/melusi-k/ate-ios/actions/runs/41184200200); Compile failed [41184200185](https://github.com/melusi-k/ate-ios/actions/runs/41184200185) at #145 and #195; docs validation skipped. | Blocked: adds `continue-on-error: true` to required regression #83; proposes A-SHARE-05 N/A without a qualifying recorded human approval; A-WIDGET-05 Pass lacks device/build details. |
| [#181](https://github.com/melusi-k/ate-ios/pull/181) | Carryover / supersession candidate | 21 ahead / 243 behind main; draft; three unresolved threads; no exact-head Compile/Dogfood evidence. | Do not double-count with #206/#231. Retain until explicit supersession/closure decision. |
| [#66](https://github.com/melusi-k/ate-ios/pull/66) | Carryover | 38 ahead / 595 behind main; draft; no exact-head Compile/Dogfood evidence; no approval. | Reconcile/split manually; preserve strict accessibility assertions. Device/Shortcuts evidence remains in #67. |

No branch was rewritten. GitHub update-branch is disabled and the connected integration exposes no safe rebase operation.

### Repository merge governance

- Ruleset [main-production-protection](https://github.com/melusi-k/ate-ios/rules/26236404) exists with `enforcement=disabled`. Its configured requirements include one approving review, resolved review threads, strict `compile` and `dogfood-qualification` checks, and linear history.
- `.github/CODEOWNERS` exists with `* @melusi-k`, but the ruleset has `require_code_owner_review=false`. The sole owner is the PR author; nominate an independent maintainer/team before requiring owner approval.
- Repository metadata: squash merge enabled, auto-merge disabled, update-branch disabled. Branch-protection API access remains 403, so separate branch protection is unverified.
- No governance setting was changed. Do not auto-merge while ruleset enforcement and independent ownership/review requirements are unverified.

### Lifecycle reconstruction addendum

All timestamps below are exact GitHub UTC metadata/commit timestamps; SAST is UTC+02:00. Actual work start is not equated with ticket or PR creation.

| Ticket | Event | UTC | SAST | Confidence |
|---|---|---|---|---|
| [Issue #179](https://github.com/melusi-k/ate-ios/issues/179) | Created | 2026-10-25T01:45:00Z | 2026-10-25 03:45:00 | Verified |
| Issue #179 | First recorded activity: cross-reference to #180 | 2026-10-25T01:48:25Z | 2026-10-25 03:48:25 | Verified |
| Issue #179 | Actual work start: earliest linked implementation commit in #181, `d3a141de8c61f33194b712819a18b07d74c2362a` | 2026-10-25T06:40:40Z | 2026-10-25 08:40:40 | Inferred earliest observable activity |
| [PR #206](https://github.com/melusi-k/ate-ios/pull/206) | Created / opened | 2026-10-30T17:10:20Z | 2026-10-30 19:10:20 | Verified |
| PR #206 | First recorded activity: GitHub Project automation | 2026-10-30T17:10:22Z | 2026-10-30 19:10:22 | Verified |
| PR #206 | First substantive human review: author COMMENTED self-review; not approval | 2026-10-30T17:38:28Z | 2026-10-30 19:38:28 | Verified |
| PR #206 | Actual work start: earliest implementation commit `02571a4ced4eb2f126aaad345d4b93bfbaa7cad1` | 2026-10-30T20:08:27Z | 2026-10-30 22:08:27 | Inferred earliest observable activity |
| [PR #231](https://github.com/melusi-k/ate-ios/pull/231) | Created / opened | 2026-10-31T06:34:20Z | 2026-10-31 08:34:20 | Verified |
| PR #231 | Actual work start: earliest implementation commit `3ab5a8d6a8c9b53ad5be10fe944732d813cc154d` | 2026-10-31T06:33:58Z | 2026-10-31 08:33:58 | Inferred earliest observable activity |
| PR #231 | First human review / approval | Unknown / none verified | Unknown / none verified | Unknown |
| [PR #234](https://github.com/melusi-k/ate-ios/pull/234) | Created / opened | 2026-10-31T07:30:58Z | 2026-10-31 09:30:58 | Verified |
| PR #234 | Actual work start: earliest implementation commit `af9563e4f454381003f632b7d01bbcb75f4111a2` | 2026-10-31T07:25:42Z | 2026-10-31 09:25:42 | Inferred earliest observable activity |
| PR #234 | Codex review summary (automated, not a human review) | 2026-10-31T07:31:03Z | 2026-10-31 09:31:03 | Verified |
| PR #234 | First substantive human review / approval | Unknown / none verified | Unknown / none verified | Unknown |

Existing lifecycle records for #66 and #181 remain unchanged: their first implementation commits and COMMENTED human reviews are already recorded in the preceding lifecycle table. Neither has a qualifying approval or completion event.

### Timing and sprint metrics

- PR #206 time from PR open to first human COMMENTED review: **28m 08s** (Verified endpoints; self-review, not approval).
- PR #181 and #66 first-review intervals remain the previously recorded samples; both first reviews were COMMENTED, not approvals.
- PR #231 and #234 have no verified human review or approval timestamps.
- No qualifying approval time, merge/close time, or accepted completion time exists for #179/#206/#231/#234. Lead time, implementation time and cycle time are not calculated for these open tickets.
- W44 commitment accuracy and carryover rate remain **unavailable** because no committed W44 denominator was recorded.

### Next actions

1. Fix #206 diary corruption preservation and daily-total overflow; wait for exact-head Compile and Dogfood to finish, then obtain independent approval.
2. Keep #231 draft; after #206 is accepted/merged, reconcile the child to current main and rerun all exact-head tests.
3. Fix #234 by removing the #83 error waiver, resolving #145/#195 failures, recording the explicit A-SHARE-05 scope decision and device evidence for A-WIDGET-05, then rerun required checks.
4. Keep #181/#66 as carryovers until maintainers decide whether to supersede/split them.
5. On Sunday 2026-11-01, close W44 with unavailable denominators stated explicitly. On Monday 2026-11-02, revalidate W45 commitments against fresh main, CI, PR reviews and release evidence.


---

## Sprint 2026-W44 — Sunday retrospective (2026-11-01)

**Sprint window:** Monday 2026-10-26 through Sunday 2026-11-01  
**Evidence cutoff:** 2026-11-01T09:58:03Z (Africa/Johannesburg: 2026-11-01 11:58:03)  
**Retrospective status:** Closed with a baseline limitation.  
**W44 committed baseline:** **Unknown / not recoverable from the records inspected.** The repository's sprint history explicitly recorded that no W44 committed baseline was available. Consequently, the following are observed W44 delivery outcomes, not claims that they were all committed sprint scope.

### Observed completed work (PRs are separate records; linked issues are not double-counted)

| Owning issue / outcome | PR delivery | Verified merge (UTC; SAST) | Merge commit |
|---|---|---|---|
| [Issue #179 — Nutrition foundation](https://github.com/melusi-k/ate-ios/issues/179) | [#206 — foundation](https://github.com/melusi-k/ate-ios/pull/206) | 2026-10-31T09:55:54Z; 2026-10-31 11:55:54 | `1e70a892afbd595deb6488efa176583796c692c8` |
| Same issue #179 | [#231 — corrupt-goals recovery child](https://github.com/melusi-k/ate-ios/pull/231) | 2026-10-31T10:56:10Z; 2026-10-31 12:56:10 | `ede74de4dc0f4743e1945e6a811154b89c64bd75` |
| Same issue #179 | [#237 — diary corruption backup/recovery](https://github.com/melusi-k/ate-ios/pull/237) | 2026-10-31T13:51:15Z; 2026-10-31 15:51:15 | `84b69545f2f47c1a63117fb4cec082aa6aefd911` |
| Same issue #179 | [#238 — curated nutrition catalogue](https://github.com/melusi-k/ate-ios/pull/238) | 2026-10-31T14:36:37Z; 2026-10-31 16:36:37 | `7d484e306ff5b9e22f98281301bdd53d6f5f0dfb` |
| [Issue #245 — Food Journal](https://github.com/melusi-k/ate-ios/issues/245) | [#246 — product contract](https://github.com/melusi-k/ate-ios/pull/246) | 2026-10-31T21:28:36Z; 2026-10-31 23:28:36 | `8b02e4109c00dfea0c25af4401140a7aedb16d0c` |
| Same issue #245 | [#247 — entry kind/day semantics and store groundwork](https://github.com/melusi-k/ate-ios/pull/247) | 2026-11-01T03:18:03Z; 2026-11-01 05:18:03 | `94731887c7c0986ca5d73dca761c0226e85d4765` |
| Same issue #245 | [#250 — journal open-state recovery](https://github.com/melusi-k/ate-ios/pull/250) | 2026-11-01T05:43:24Z; 2026-11-01 07:43:24 | `9bb8fdb80bce2bcc6195d66ed15b1a27859b4194` |
| [Issue #253 — generation correctness](https://github.com/melusi-k/ate-ios/issues/253) | [#255 — source-context correction](https://github.com/melusi-k/ate-ios/pull/255) | 2026-11-01T07:56:38Z; 2026-11-01 09:56:38 | `7427ed69962fdf013428fc4e59629436bcc7f98f` |
| Sprint records | [#236 — W45 Guardian evidence refresh](https://github.com/melusi-k/ate-ios/pull/236) | 2026-10-31T14:46:34Z; 2026-10-31 16:46:34 | `5d6705e2cd9104726d2a10105d5793d817aa8985` |

The linked nutrition PRs #206/#231/#237/#238 represent one issue-level nutrition outcome, not four independent product deliveries. Likewise, #246/#247/#250 are one Food Journal issue outcome, and #255 is a partial generation outcome under #253. Issues #179, #245 and #253 remain open; their actual completion is **Unknown**, not the merge date of one constituent PR.

### Blocked, in progress and carry-forward work

| Work | W44 close-out evidence | Disposition |
|---|---|---|
| [#239 — nutrition diary CI/root stack](https://github.com/melusi-k/ate-ios/pull/239) | Exact-head Compile failed: `CoverageUITests.test32_MoreCollectionsToolsAbout` timed out while evaluating a UI query. Dogfood and open-state UI passed. No approval. | Carry-forward candidate; fix/re-run Compile and obtain independent review. |
| [#240 — diary editing child](https://github.com/melusi-k/ate-ios/pull/240) | Compile cancelled; no current exact-head Dogfood evidence; child of #239. | Wait for #239, then reconcile and revalidate. |
| [#241 — weekly totals child](https://github.com/melusi-k/ate-ios/pull/241) | Compile cancelled; no current exact-head Dogfood evidence; child of #240. The PR removes explicit pass-evidence guards for edit tests and removes the edit-flow UI test from the current test file. | Restore/replace the edit-flow test and its pass-evidence guard; do not weaken the gate. |
| [#251 — Food Journal discovery](https://github.com/melusi-k/ate-ios/pull/251) | 73 commits ahead / 8 behind current main; Compile, Dogfood, open-state UI and discovery UI queued; no approval. | Manual reconciliation with current main; W45 candidate, not committed yet. |
| [#254 — generation pipeline](https://github.com/melusi-k/ate-ios/pull/254) | Compile passed, but Dogfood failed at `KeyFlowsQATests.testQA5_Share` (missing “Share as text”) and open-state UI failed at `JournalOpenStateUITests.testHealthyOpenShowsNoBanner` (app launch timeout). Device golden-set evaluation not recorded. | Fix/re-run both failures and complete on-device evaluation; no merge. |
| [#259 — shared-build CI proof](https://github.com/melusi-k/ate-ios/pull/259) | Proof build and open-state UI passed; Compile in progress; proof unit/KeyFlows tests and Dogfood queued. | W45 candidate only; proof prototype is not a substitute for required validation. |
| [#260 — AI model lane architecture](https://github.com/melusi-k/ate-ios/pull/260) | Compile, AI preflight and open-state UI in progress; Dogfood queued. No approval. The new model test target is included in the default `Ate` scheme test action; the documented unfiltered local test command would therefore run it on non-eligible devices. | Isolate the model-readiness target or explicitly scope the default scheme; remove the temporary PR trigger before merge. |
| [#234 — QA scope changes](https://github.com/melusi-k/ate-ios/pull/234) | 22 ahead / 133 behind main; Compile failed at Settings About/timer #145 and Insights acceptance #195; Dogfood passed. It adds `continue-on-error` to required regression #83 and changes A-SHARE-05/A-WIDGET-05 status without qualifying independent approval/device evidence. | Blocked; restore hard failure semantics and obtain explicit scope/device evidence before changing the QA denominator. |
| [#181 — older nutrition PR](https://github.com/melusi-k/ate-ios/pull/181) | Draft, 21 ahead / 373 behind, three unresolved threads, no exact-head Compile/Dogfood evidence. | Carryover/supersession decision required; overlaps work now merged and the #239–#241 follow-up stack. |
| [#66 — Journal acceptance UI](https://github.com/melusi-k/ate-ios/pull/66) | Draft, 38 ahead / 725 behind, no exact-head Compile/Dogfood evidence. | Carryover; reconcile against #247/#250 and keep physical-device acceptance in #67. |

### Release and governance outcome

Current main at close-out is `7427ed69962fdf013428fc4e59629436bcc7f98f`. Release readiness remains **BLOCKED**. Issue #33's latest recorded snapshot (Build IPA run [41286777216](https://github.com/melusi-k/ate-ios/actions/runs/41286777216)) reports 1/59 verified, 12 failing and 46 open; required unit, 8-flow QA, UI and E2E jobs were skipped, and QA-results retrieval returned HTTP 400. A successful workflow wrapper with skipped gates is not release acceptance.

The `main-production-protection` ruleset exists but has enforcement **disabled**; the main branch reports `protected=false`. The configured rule requires one approval, review-thread resolution and strict `compile`/`dogfood-qualification` checks, but none is enforced. CODEOWNERS is `.github/CODEOWNERS` with `* @melusi-k`; CODEOWNERS review is disabled and the only owner is also the repository author. Squash merge is enabled; auto-merge and update-branch are disabled.

Review metadata shows the W44 merged PRs #206, #231, #237, #238, #246, #247, #250 and #255 had no qualifying APPROVED review. PR #206 had only an author COMMENTED self-review; the others had no submitted review. This does not invalidate their merge timestamps, but it is a material governance/control failure enabled by the disabled ruleset. No repository policy was changed during this retrospective.

### Lessons and next actions

1. Record the committed baseline before work begins. Without it, W44 commitment accuracy and carryover rate cannot be calculated.
2. Keep issue-level outcomes separate from PR stack steps. Count #206/#231/#237/#238 once under #179; #246/#247/#250 once under #245; #255 as a partial #253 outcome.
3. Never equate a skipped, cancelled, queued or failed check with a pass. Exact-head evidence is required.
4. Do not weaken the regression gate or change release denominator statuses without explicit evidence and an approved scope decision.
5. Enable effective independent review/status enforcement and nominate independent CODEOWNERS before autonomous merging.
6. On Monday 2026-11-02, revalidate W45 against current main. Preserve the original W45 dates (2026-11-02 to 2026-11-08) and original history. The original #206 implementation slice and #231 recovery child were completed before W45 began; #179 remains open for follow-up. Assess #239–#241 as a possible single W45 nutrition outcome only after the root CI failure and test-gate issue are resolved. Keep #30 committed and #70 stretch per the existing baseline. #251, #254, #259 and #260 are candidates, not W45 commitments, until Monday capacity/dependency review. No new dates are assigned to them in this Sunday close-out.

### W44 metrics

- W44 commitment accuracy: **Unavailable** — no recoverable committed-scope denominator.
- W44 carryover rate: **Unavailable** — no recoverable committed-scope denominator.
- Issue lead time / cycle time: **Not calculable** for #179, #245 and #253 because all remain open and actual completion is Unknown.
- Implementation time: **Not calculated** from first-commit timestamps; those are inferred earliest observable implementation evidence, not verified human work-start events.
- Review/approval time: **Unavailable** for the merged W44 PRs because no qualifying independent approval is recorded. Do not treat COMMENTED reviews or bot/Codex activity as approval.
- PR open-to-merge elapsed time may be derived from verified PR metadata, but it is not substituted for implementation time or issue cycle time.

## Lifecycle reconstruction addendum — 2026-11-01

All timestamps are exact UTC ISO-8601 metadata. SAST is Africa/Johannesburg (UTC+02:00). **Verified** means directly present in GitHub metadata/timeline; **Inferred** means earliest observable linked commit used as a work-start proxy; **Unknown** means no defensible event evidence. PR timelines below remain distinct from their owning issue timelines.

### Issue timelines

| Issue | Created (UTC; SAST) | First activity (UTC; SAST) | Actual work start | PR/closure/completion |
|---|---|---|---|---|
| [#179](https://github.com/melusi-k/ate-ios/issues/179) | 2026-10-25T01:45:00Z; 2026-10-25 03:45:00 | Existing history retained: first issue event was a referenced commit at 2026-10-25T21:27:10Z; 2026-10-25 23:27:10 (Verified) | 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 (Inferred from earliest linked PR #181 commit) | PRs #206/#231/#237/#238 merged as above; issue still open; actual completion Unknown. |
| [#245](https://github.com/melusi-k/ate-ios/issues/245) | 2026-10-31T20:55:12Z; 2026-10-31 22:55:12 (Verified) | 2026-10-31T20:55:15Z; 2026-10-31 22:55:15, `added_to_project_v2` by project automation (Verified) | 2026-10-31T20:55:44Z; 2026-10-31 22:55:44 (Inferred from earliest linked PR #246 commit `358cb4c9`) | PRs #246/#247/#250 merged; #251 remains open; issue still open; actual completion Unknown. |
| [#253](https://github.com/melusi-k/ate-ios/issues/253) | 2026-11-01T04:49:56Z; 2026-11-01 06:49:56 (Verified) | 2026-11-01T04:49:58Z; 2026-11-01 06:49:58, label event by automation (Verified) | 2026-11-01T04:50:43Z; 2026-11-01 06:50:43 (Inferred from earliest linked PR #254 commit) | PR #255 merged as a partial fix; #254 remains open; issue still open; actual completion Unknown. |
| [#138](https://github.com/melusi-k/ate-ios/issues/138) | 2026-10-20T23:59:51Z; 2026-10-21 01:59:51 (Verified) | 2026-10-20T23:59:53Z; 2026-10-21 01:59:53, label event (Verified) | Unknown | #259 is an open proof prototype; issue still open; completion Unknown. |
| [#195](https://github.com/melusi-k/ate-ios/issues/195) | 2026-10-30T07:30:05Z; 2026-10-30 09:30:05 (Verified) | 2026-10-30T07:30:06Z; 2026-10-30 09:30:06, label event (Verified) | Unknown | Issue still open; completion Unknown. |
| [#30](https://github.com/melusi-k/ate-ios/issues/30) | Existing history retained: 2026-10-11T22:50:12Z; 2026-10-12 00:50:12 | Existing history retained: 2026-10-11T22:50:13Z; 2026-10-12 00:50:13, label event | Unknown | Still open; actual completion Unknown. |
| [#33](https://github.com/melusi-k/ate-ios/issues/33) | 2026-10-11T22:56:59Z; 2026-10-12 00:56:59 (Verified) | 2026-10-11T22:57:00Z; 2026-10-12 00:57:00, assignment event (Verified) | Unknown | Still open; release gate blocked; actual completion Unknown. |

### PR timelines

| PR | Opened (UTC; SAST) | First activity (UTC; SAST) | Actual work start (UTC; SAST) | Human review / approval | Merged (UTC; SAST) |
|---|---|---|---|---|---|
| [#206](https://github.com/melusi-k/ate-ios/pull/206) | 2026-10-30T17:10:20Z; 2026-10-30 19:10:20 (Verified) | Unknown in this addendum | 2026-10-30T20:08:27Z; 2026-10-30 22:08:27 (Inferred earliest commit) | 2026-10-30T17:38:28Z; 2026-10-30 19:38:28 — author COMMENTED self-review, not approval; no qualifying approval | 2026-10-31T09:55:54Z; 2026-10-31 11:55:54 (Verified) |
| [#231](https://github.com/melusi-k/ate-ios/pull/231) | 2026-10-31T06:34:20Z; 2026-10-31 08:34:20 (Verified) | Unknown in this addendum | 2026-10-31T06:33:58Z; 2026-10-31 08:33:58 (Inferred earliest commit) | No submitted human review; no approval | 2026-10-31T10:56:10Z; 2026-10-31 12:56:10 (Verified) |
| [#237](https://github.com/melusi-k/ate-ios/pull/237) | 2026-10-31T11:14:56Z; 2026-10-31 13:14:56 (Verified) | Unknown | 2026-10-31T11:10:29Z; 2026-10-31 13:10:29 (Inferred earliest commit) | No submitted human review; no approval | 2026-10-31T13:51:15Z; 2026-10-31 15:51:15 (Verified) |
| [#238](https://github.com/melusi-k/ate-ios/pull/238) | 2026-10-31T11:32:42Z; 2026-10-31 13:32:42 (Verified) | Unknown | 2026-10-31T11:31:06Z; 2026-10-31 13:31:06 (Inferred earliest commit) | No submitted human review; no approval | 2026-10-31T14:36:37Z; 2026-10-31 16:36:37 (Verified) |
| [#239](https://github.com/melusi-k/ate-ios/pull/239) | 2026-10-31T14:48:54Z; 2026-10-31 16:48:54 (Verified) | 2026-10-31T14:48:55Z; 2026-10-31 16:48:55, project automation (Verified) | 2026-10-31T14:46:42Z; 2026-10-31 16:46:42 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#240](https://github.com/melusi-k/ate-ios/pull/240) | 2026-10-31T14:51:06Z; 2026-10-31 16:51:06 (Verified) | 2026-10-31T14:51:08Z; 2026-10-31 16:51:08, project automation (Verified) | 2026-10-31T14:49:38Z; 2026-10-31 16:49:38 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#241](https://github.com/melusi-k/ate-ios/pull/241) | 2026-10-31T15:03:41Z; 2026-10-31 17:03:41 (Verified) | 2026-10-31T15:03:42Z; 2026-10-31 17:03:42, project automation (Verified) | 2026-10-31T15:00:56Z; 2026-10-31 17:00:56 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | 2026-10-31T07:30:58Z; 2026-10-31 09:30:58 (Verified) | 2026-10-31T07:31:00Z; 2026-10-31 09:31:00, project automation (Verified) | 2026-10-31T07:25:42Z; 2026-10-31 09:25:42 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#181](https://github.com/melusi-k/ate-ios/pull/181) | Existing history retained: 2026-10-25T06:44:01Z; 2026-10-25 08:44:01 | Existing history retained: 2026-10-25T06:44:10Z; 2026-10-25 08:44:10, bot label | Existing history retained: 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 (Inferred) | 2026-10-30T05:02:18Z; 2026-10-30 07:02:18 — author COMMENTED review, not approval; three unresolved threads | Not merged |
| [#66](https://github.com/melusi-k/ate-ios/pull/66) | Existing history retained: 2026-10-12T23:14:40Z; 2026-10-13 01:14:40 | Existing history retained: 2026-10-12T23:15:05Z; 2026-10-13 01:15:05, cross-reference | Existing history retained: 2026-10-12T23:13:39Z; 2026-10-13 01:13:39 (Inferred) | 2026-10-13T03:39:11Z; 2026-10-13 05:39:11 — author COMMENTED review, not approval; no qualifying approval | Not merged |
| [#246](https://github.com/melusi-k/ate-ios/pull/246) | 2026-10-31T20:55:50Z; 2026-10-31 22:55:50 (Verified) | Unknown | 2026-10-31T20:55:44Z; 2026-10-31 22:55:44 (Inferred earliest commit) | No submitted human review; no approval | 2026-10-31T21:28:36Z; 2026-10-31 23:28:36 (Verified) |
| [#247](https://github.com/melusi-k/ate-ios/pull/247) | 2026-10-31T21:15:01Z; 2026-10-31 23:15:01 (Verified) | Unknown | 2026-10-31T21:13:23Z; 2026-10-31 23:13:23 (Inferred earliest commit) | No submitted human review; no approval | 2026-11-01T03:18:03Z; 2026-11-01 05:18:03 (Verified) |
| [#250](https://github.com/melusi-k/ate-ios/pull/250) | 2026-11-01T03:24:39Z; 2026-11-01 05:24:39 (Verified) | Unknown | 2026-11-01T03:21:50Z; 2026-11-01 05:21:50 (Inferred earliest commit) | No submitted human review; no approval | 2026-11-01T05:43:24Z; 2026-11-01 07:43:24 (Verified) |
| [#251](https://github.com/melusi-k/ate-ios/pull/251) | 2026-11-01T03:54:28Z; 2026-11-01 05:54:28 (Verified) | 2026-11-01T03:54:30Z; 2026-11-01 05:54:30, project automation (Verified) | 2026-11-01T03:52:21Z; 2026-11-01 05:52:21 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#254](https://github.com/melusi-k/ate-ios/pull/254) | 2026-11-01T04:53:24Z; 2026-11-01 06:53:24 (Verified) | 2026-11-01T04:53:26Z; 2026-11-01 06:53:26, project automation (Verified) | 2026-11-01T04:50:43Z; 2026-11-01 06:50:43 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#255](https://github.com/melusi-k/ate-ios/pull/255) | 2026-11-01T05:20:32Z; 2026-11-01 07:20:32 (Verified) | Unknown | 2026-11-01T05:19:08Z; 2026-11-01 07:19:08 (Inferred earliest commit) | No submitted human review; no approval | 2026-11-01T07:56:38Z; 2026-11-01 09:56:38 (Verified) |
| [#259](https://github.com/melusi-k/ate-ios/pull/259) | 2026-11-01T09:10:08Z; 2026-11-01 11:10:08 (Verified) | 2026-11-01T09:10:10Z; 2026-11-01 11:10:10, project automation (Verified) | 2026-11-01T09:09:57Z; 2026-11-01 11:09:57 (Inferred earliest commit) | No submitted human review; no approval | Not merged |
| [#260](https://github.com/melusi-k/ate-ios/pull/260) | 2026-11-01T09:19:48Z; 2026-11-01 11:19:48 (Verified) | 2026-11-01T09:19:50Z; 2026-11-01 11:19:50, project automation (Verified) | 2026-11-01T09:17:58Z; 2026-11-01 11:17:58 (Inferred earliest commit) | No submitted human review; no approval | Not merged |

No first qualifying approval was found for the listed PRs. For merged PRs, the merge event is verified but does not prove the parent issue's actual completion. For open PRs, merge and actual completion are Unknown/Not merged. All human COMMENTED reviews above are explicitly not approvals; bot/Codex activity is excluded from human review.

### Metrics and denominator guard

No issue lead time, implementation time, or issue cycle time is calculated for #179, #245 or #253 because the issues remain open and actual completion is Unknown. Earliest commit timestamps are Inferred work-start proxies, not verified human start times. No approval-time sample exists for the merged W44 PRs because no qualifying approval was submitted. W44 commitment accuracy and carryover rate remain unavailable because the committed-scope denominator is missing. Preserve the prior W45 planning proposal and its original planned dates; the Monday 2026-11-02 planning review must append any new scope/date decisions rather than rewrite this history.


## Post-close CI status delta — 2026-11-01T10:05:26Z (SAST 12:05:26)

This is an append-only update after the W44 evidence cutoff above; it does not alter the 09:58:03Z snapshot.

- **PR #260:** AI model preflight failed at 2026-11-01T10:02:06Z because the simulator reported `modelNotReady` (model assets not downloaded/ready); open-state UI failed at 10:02:55Z because `JournalOpenStateUITests.testHealthyOpenShowsNoBanner` timed out launching the app. Compile remained in progress and Dogfood was queued at the latest poll. This confirms the lane is not ready for merge.
- **PR #259:** proof-build and open-state UI passed; Compile remained in progress; proof KeyFlows and Dogfood were in progress; proof unit tests were queued. This is still incomplete and is not a substitute for required gates.
- **PR #261 (this documentation PR):** docs-validation passed; the stack validator passed after the PR body was corrected to the repository's required bold Stack metadata format. App Compile was skipped by the docs-only path; Dogfood and open-state UI remained queued. The PR remains draft and unapproved.
