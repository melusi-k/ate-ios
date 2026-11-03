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


## Sprint 2026-W45 Monday plan and evidence revalidation — 2026-11-02

**Planning observation:** 2026-11-02T06:39:30Z (2026-11-02 08:39:30 Africa/Johannesburg).  
**Sprint window:** Monday 2026-11-02 through Sunday 2026-11-08. The original W45 planned dates are preserved. Actual sprint work start/end remain **Unknown**; the planning observation is not implementation-start evidence.

### Monday decision

| Work | W45 disposition | Planned dates | Outcome accounting |
|---|---|---|---|
| [#30 — release readiness follow-up](https://github.com/melusi-k/ate-ios/issues/30) | **Committed — bounded evidence refresh** | 2026-11-02 to 2026-11-08 | One issue-level outcome: current-main go/no-go evidence and a prioritized blocker plan. This is not a release approval. |
| [#179 — nutrition tracking](https://github.com/melusi-k/ate-ios/issues/179) | **Committed — at risk / entry-gated** | 2026-11-02 to 2026-11-08 | One bounded diary/goals increment through PRs #239 → #240 → #241. Count the parent outcome once; retain each PR as a separate lifecycle ticket. Do not claim all of #179 or Phase 1 is complete. |
| [#70 — requirements/QA ownership reconciliation](https://github.com/melusi-k/ate-ios/issues/70) | **Stretch only** | 2026-11-05 to 2026-11-08 | At most one separately verifiable high-risk evidence/ownership mismatch; not the full coverage-map audit. |
| [#181](https://github.com/melusi-k/ate-ios/pull/181), [#66](https://github.com/melusi-k/ate-ios/pull/66) | Carryover / not committed | No W45 dates | Preserve until an explicit supersession/reconciliation decision and fresh exact-head evidence exist. |
| [#251](https://github.com/melusi-k/ate-ios/pull/251), [#254](https://github.com/melusi-k/ate-ios/pull/254), [#263](https://github.com/melusi-k/ate-ios/pull/263), [#266](https://github.com/melusi-k/ate-ios/pull/266) | Candidate / not committed | No W45 dates | Reconsider only when their own dependencies, exact-head checks and independent review are satisfied. |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | Blocked / not selected | No W45 dates | Proposes changing QA scope and adding continue-on-error to required regression #83; do not merge or treat the proposed denominator change as accepted. |
| [#259](https://github.com/melusi-k/ate-ios/pull/259) | Closed without merge | N/A | Shared-build proof prototype was not adopted; no CI turnaround improvement is assumed. |
| [#265](https://github.com/melusi-k/ate-ios/pull/265), [#262](https://github.com/melusi-k/ate-ios/pull/262) | Branch synchronization only | N/A | Not independent product deliveries and not throughput outcomes. |

### Product, backlog and acceptance-source review

- **Main baseline at planning time:** 2616420eaa16d83a9df646874be3021d08b6d393. It includes the recent merged work described below.
- **PRD:** the implementation-audit banner is dated 2026-10-24 and references an older main SHA and a 44/59 readiness snapshot. It is historical, not current evidence.
- **MVP checklist:** its progress snapshot is also dated 2026-10-24. The nutrition rows C-NUT-01 through C-NUT-04 remain Partial; their device and current-main evidence is not established by this snapshot.
- **QA matrix:** 179 checklist IDs and 179 linked rows, plus two supplemental platform rows; it explicitly asserts no current pass percentage. The nutrition rows still say exact-head CI pending and device results not run.
- **Gap register:** its structural audit still describes 176 unique IDs/rows/owner links. That does not reconcile with the QA matrix's 179/179 inventory. Treat this as an open #70 discrepancy, not as proof that either inventory is behaviorally complete.
- **Product backlog index:** its migration status is dated 2026-10-22 and the Health and Journal index does not yet list newer issues #179, #245 or #253. The GitHub issue tracker remains authoritative until the index is reconciled.
- **QA and CI policy:** docs/QA.md and .github/workflows/build-ipa.yml agree that ordinary pushes to main are artifact-only. Full Build IPA validation is opt-in through workflow_dispatch run_tests or a commit message containing [run tests]. The previous W44 note in #70 claiming every main push sets RUN_TESTS=true is incorrect; an append-only correction is recorded in #70 below.
- **Nutrition source status:** PR #238 merged 30 source-traceable USDA SR Legacy records and the FDC policy permits this public-domain source. SAFOODS commercial reuse rights remain unconfirmed. The checklist and QA matrix still describe the verified catalogue as empty; reconcile that stale wording and verify the bundled records on a current exact main SHA before changing C-NUT-03 to Complete. The 30 records do not establish broad South African food coverage or complete #179.
- **Generation/AI validation:** merged PR #260 establishes separate standard, AI-ready real-model and physical-device lanes. The hosted xcode-27 run returned modelNotReady and skipped inference; a hosted simulator is not evidence of real-model output quality. PR #254's 11-fixture device golden-set evaluation remains pending.

### Committed scope, dependencies and acceptance

#### #30 — release-readiness evidence refresh

**Commitment:** committed; planned 2026-11-02 to 2026-11-08.

**Outcome:** refresh the release decision against a named exact main SHA, enumerate each gate as pass/fail/skipped/not run/unknown, and maintain an owner/action/dependency list for the remaining blockers. A successful workflow wrapper or artifact build is not a release decision.

**Dependencies and current baseline:**
- [Issue #33](https://github.com/melusi-k/ate-ios/issues/33), current main SHA and exact-run job results.
- Build IPA run [41328117329](https://github.com/melusi-k/ate-ios/actions/runs/41328117329) was a main push on SHA 2616420eaa16d83a9df646874be3021d08b6d393. The artifact workflow concluded success, but Run unit tests, KeyFlows QA, Cooking Tracker/Cook Mode, shared-navigation regressions, UI shards, backend E2E and beta promotion were skipped. This is an artifact-only build, not full qualification.
- Release-readiness wrapper [41330257168](https://github.com/melusi-k/ate-ios/actions/runs/41330257168) concluded success, but issue #33's generated report remains **BLOCKED**: 1/59 verified, 12 failing, 46 open; unit, 8-flow QA, UI and E2E skipped; qa_results retrieval returned HTTP 400.
- The report lists failures in timer completion, sign-in, password reset, magic link, rate-limit/offline auth handling, offline sync/local-library stability, backend-unavailable fallback, real-iPhone core flows, crash paths and background/relaunch behavior. It also records two unresolved and three accepted blockers.

**Acceptance criteria:**
1. Record the exact candidate SHA and link every required workflow/job result; do not substitute wrapper success for inner-gate evidence.
2. Refresh #33's blocker ledger, separating product failures, skipped validation, external/device dependencies and accepted constraints.
3. Keep the disposition BLOCKED while required evidence is skipped, failed, stale or missing; record a human release decision only when the evidence and signoffs exist.
4. Keep production sharing/security, Universal Links, real-account/device evidence and external Apple-account constraints distinct.
5. Do not change branch protection, rulesets, required checks or QA denominators as part of this work.

#### #179 — bounded diary/goals follow-up stack

**Commitment:** retain the W45 issue-level commitment as **at risk / entry-gated**, planned 2026-11-02 to 2026-11-08. The issue and PRs remain separate lifecycle tickets; the shared feature outcome is counted once.

**Delivery sequence:**
1. [PR #239](https://github.com/melusi-k/ate-ios/pull/239) — root: wire diary/goals/catalogue and accessibility coverage into required validation.
2. [PR #240](https://github.com/melusi-k/ate-ios/pull/240) — child of #239: edit logged diary entries while preserving identity, local day and untouched precision.
3. [PR #241](https://github.com/melusi-k/ate-ios/pull/241) — child of #240: current-calendar-week nutrient totals; no weekly goals.

**Current exact-head evidence and blockers:**
- PR #239 head 308cf71078a09911d70abe7f00bafd4b987a761c is based on old main 7427ed69962fdf013428fc4e59629436bcc7f98f, not current main. Exact-head Dogfood passed [41307451102](https://github.com/melusi-k/ate-ios/actions/runs/41307451102). Its nutrition-focused unit selection executed 53 tests with zero failures, and the nutrition diary/goals/accessibility UI selection executed 14 tests with zero failures in [Compile run 41307451114](https://github.com/melusi-k/ate-ios/actions/runs/41307451114). However, the overall Compile check failed on CookingTrackerEntry month-navigation assertions, Cook Mode completion process termination, and CookIngredients large-text UI-query timeout. Separate open-state UI run [41307451213](https://github.com/melusi-k/ate-ios/actions/runs/41307451213) failed because JournalOpenStateUITests.testHealthyOpenShowsNoBanner timed out launching the app. These are real blocking failures even though the nutrition-focused selections passed.
- PR #240 head 98f71aad2c75ac361cf3dcff18e79c84dce1b3f4 is based on an older #239 head 03c6725ef375d3cc1b219ed066c38939e204442b. Its Compile run [41259962103](https://github.com/melusi-k/ate-ios/actions/runs/41259962103) was cancelled; no current exact-head Dogfood evidence was found. GitHub currently reports mergeable=false.
- PR #241 head 38d04465636f962634405d2b54c25e29a0016453 is based on an older #240 head f20f7a83381685e7a8a8b7e2cd52a903c174534a. Its Compile run [41260002276](https://github.com/melusi-k/ate-ios/actions/runs/41260002276) was cancelled; no current exact-head Dogfood evidence was found. It removes the edit-flow UI test and named pass-evidence guard; restore or replace both before consideration.
- No qualifying human approval or submitted human review was found for #239, #240 or #241. No review threads were returned for these three PRs. Current branches require manual reconciliation; repository update-branch is disabled.
- PR #238 is merged and added 30 USDA SR Legacy records. The old checklist/QA statement that the verified catalogue is empty is now stale; verify the source records and update evidence before claiming C-NUT-03 complete.

**Dependencies:** root #239 must be reconciled to current main and the failed shared regressions diagnosed/fixed or validly rerun; #240 must be retargeted to the accepted #239 head; #241 must be retargeted to the accepted #240 head and restore edit coverage/pass guards; all final heads need exact Compile and Dogfood passes, independent approval and resolved review threads. The catalogue/source-rights status remains a separate parent-issue acceptance dependency.

**Acceptance criteria:**
1. Diary add/delete, goals recovery and incomplete-nutrition behavior remain covered; the nutrition-focused 53-unit/14-UI pass evidence is repeated on the final reconciled heads.
2. Edit preserves entry identity, local calendar day and untouched values; tests cover edit and recalculated totals.
3. Weekly totals use persisted local-day semantics; empty weeks and unknown nutrients remain explicit; no weekly goals are introduced.
4. Corrupt diary/goals data is backed up before reset; backup failure preserves original bytes.
5. All required exact-head checks pass; no required test is removed, waived, skipped or counted as a pass without execution; independent review and thread resolution are present.
6. Keep #179 open until its wider initiative acceptance, including source-backed recipe nutrition and the remaining product/device evidence, is genuinely complete.

**Adaptive checkpoint:** re-evaluate on Wednesday 2026-11-04. If #239 is still red on the reconciled head or #241's edit-coverage guard is not restored, de-scope #240/#241 to carryover rather than compressing validation or weakening a gate. Any verified root-only slice must be described narrowly.

#### #70 — stretch only

**Planned dates:** 2026-11-05 to 2026-11-08. **Commitment:** stretch, not committed.

Bound the work to one high-risk evidence/ownership discrepancy surfaced by #30. The first candidate is the incorrect W44 statement about Build IPA trigger behavior: ordinary main pushes are artifact-only; full validation is opt-in. docs/QA.md already describes this correctly. A separate structural discrepancy remains: gap register 176 versus QA matrix 179. Do not attempt the full 179-row coverage audit in this sprint.

**Acceptance:** one named discrepancy, authoritative source, affected requirement/owner, exact run or test evidence, append-only correction and explicit resolved/unresolved disposition. No acceptance IDs, release-gate classes, denominators or CI enforcement are changed without an explicit decision.

### Rolling-sprint execution rule

Do not wait for Sunday when committed work finishes early. Once #30 and the bounded #179 outcome are genuinely accepted with exact evidence, pull #70's single bounded stretch item first. After that, reconsider #251 only after main reconciliation, green exact-head Compile/Dogfood and independent review; reconsider #254 only after its CI failures and device golden-set evaluation are complete. #263/#266 remain lower-priority documentation candidates, and #234 remains blocked. A PR merge alone never completes its parent issue.

### CI, release and governance snapshot

- Current release disposition is **BLOCKED**, not ready. Build IPA push success on 2616420 is artifact-only because all validation steps were skipped. The readiness wrapper success does not change #33's 1/59, 12 failing, 46 open disposition.
- PR #251: Compile failed [41333393413](https://github.com/melusi-k/ate-ios/actions/runs/41333393413); Dogfood, open-state UI and discovery UI passed. No human approval.
- PR #254: Compile failed [41329003425](https://github.com/melusi-k/ate-ios/actions/runs/41329003425), open-state UI failed [41329003365](https://github.com/melusi-k/ate-ios/actions/runs/41329003365), Dogfood passed. The 11-fixture on-device golden-set baseline remains pending.
- PR #266: docs-validation passed, Compile was skipped, Dogfood failed [41338655777](https://github.com/melusi-k/ate-ios/actions/runs/41338655777) and open-state UI failed [41338655767](https://github.com/melusi-k/ate-ios/actions/runs/41338655767). Documentation-only scope does not waive the checks that did run.
- PR #234: Compile failed and Dogfood passed; its proposed continue-on-error for #83 and A-SHARE-05 N/A change remain unapproved and unaccepted.
- PR #263 is draft/evidence-only. PR #265 is a main-to-feature sync PR, not a product delivery.
- The main-production-protection ruleset (ID 26236404) still has enforcement **disabled**. Its configured one-approval, resolved-thread and strict compile/dogfood rules are therefore not enforced. Branch-protection details returned 403, so no separate branch protection is assumed. CODEOWNERS review is not required. Repository settings still report auto-merge and update-branch disabled. No governance change was made.

### Recently closed work reviewed

- Nutrition: #206, #231, #237 and #238 merged before W45; #238 added 30 USDA records. They are one parent #179 outcome, not four throughput outcomes.
- Food Journal: #246, #247 and #250 merged; #251 remains open. They are one parent #245 outcome, not three separate product outcomes.
- Generation: #255 merged as a partial #253 fix; #254 remains open and eval-gated.
- Cook Mode: issue #242 closed after PR #243 merged; PR #244 subsequently added pinned-step and timer pixel evidence. The new CookIngredients UI regression now appears in #239's failed Compile run.
- CI/model lane and lifecycle: #260, #261 and #264 merged. PR #259 closed without merge; the shared-build proof was not adopted. PR #262 merged into the #251 feature branch only, not main.
- These recent merges had no submitted human APPROVED reviews in the review metadata checked here. A merge timestamp is verified delivery metadata, not evidence of approval or parent-issue completion.

### Lifecycle reconstruction delta — 2026-11-02

All times are UTC ISO-8601 with the corresponding Africa/Johannesburg local time (UTC+02:00). **Verified** means GitHub metadata/timeline; **Inferred** means earliest observable linked commit, not a verified human start; **Unknown** means no defensible evidence. PR lifecycle remains separate from issue lifecycle.

#### Recent issue lifecycle

| Ticket | Created (UTC; SAST) | First activity (UTC; SAST) | Actual work start | Closure / actual completion |
|---|---|---|---|---|
| [#242](https://github.com/melusi-k/ate-ios/issues/242) | 2026-10-31T17:09:49Z; 2026-10-31 19:09:49 — Verified | 2026-10-31T17:09:50Z; 2026-10-31 19:09:50, label event — Verified | 2026-10-31T16:24:28Z; 2026-10-31 18:24:28 — Inferred from earliest PR #243 commit | Closed 2026-10-31T19:25:08Z; 2026-10-31 21:25:08 — Verified; linked PR #243 merged one second earlier |
| [#31](https://github.com/melusi-k/ate-ios/issues/31) | 2026-10-11T22:56:10Z; 2026-10-12 00:56:10 — Verified | Not reconstructed in this pass | Unknown | Still open; actual completion Unknown. It owns the current Cooking Tracker/Cook Mode regressions observed on #239. |
| [#30](https://github.com/melusi-k/ate-ios/issues/30) | 2026-10-11T22:50:12Z; 2026-10-12 00:50:12 — Verified | 2026-10-11T22:50:13Z; 2026-10-12 00:50:13, label event — Verified | Unknown | Still open; actual completion Unknown |
| [#70](https://github.com/melusi-k/ate-ios/issues/70) | 2026-10-13T04:05:22Z; 2026-10-13 06:05:22 — Verified | 2026-10-21T10:37:09Z; 2026-10-21 12:37:09, label event — Verified | Unknown | Still open; actual completion Unknown |
| [#179](https://github.com/melusi-k/ate-ios/issues/179) | 2026-10-25T01:45:00Z; 2026-10-25 03:45:00 — Verified | 2026-10-25T01:48:25Z; 2026-10-25 03:48:25, cross-reference to #180 — Verified | 2026-10-25T06:40:40Z; 2026-10-25 08:40:40 — Inferred from earliest linked PR #181 commit | Still open; actual completion Unknown |
| [#245](https://github.com/melusi-k/ate-ios/issues/245) | 2026-10-31T20:55:12Z; 2026-10-31 22:55:12 — Verified | 2026-10-31T20:55:15Z; 2026-10-31 22:55:15, project automation — Verified | 2026-10-31T20:55:44Z; 2026-10-31 22:55:44 — Inferred from PR #246 | Still open; actual completion Unknown |
| [#253](https://github.com/melusi-k/ate-ios/issues/253) | 2026-11-01T04:49:56Z; 2026-11-01 06:49:56 — Verified | 2026-11-01T04:49:58Z; 2026-11-01 06:49:58, label event — Verified | 2026-11-01T04:50:43Z; 2026-11-01 06:50:43 — Inferred from PR #254 | Still open; actual completion Unknown |
| [#33](https://github.com/melusi-k/ate-ios/issues/33) | 2026-10-11T22:56:59Z; 2026-10-12 00:56:59 — Verified | 2026-10-11T22:57:00Z; 2026-10-12 00:57:00, assignment event — Verified | Unknown | Still open; release decision BLOCKED |
| [#138](https://github.com/melusi-k/ate-ios/issues/138) | 2026-10-20T23:59:51Z; 2026-10-21 01:59:51 — Verified | 2026-10-20T23:59:53Z; 2026-10-21 01:59:53, label event — Verified | Unknown | Still open; actual completion Unknown |
| [#195](https://github.com/melusi-k/ate-ios/issues/195) | 2026-10-30T07:30:05Z; 2026-10-30 09:30:05 — Verified | 2026-10-30T07:30:06Z; 2026-10-30 09:30:06, label event — Verified | Unknown | Still open; actual completion Unknown |

#### Recent PR lifecycle

| PR | Opened (UTC; SAST) | First activity (UTC; SAST) | Actual work start (UTC; SAST) | First substantive human review / approval | Merged or closed (UTC; SAST) |
|---|---|---|---|---|---|
| [#239](https://github.com/melusi-k/ate-ios/pull/239) | 2026-10-31T14:48:54Z; 16:48:54 — Verified | 2026-10-31T14:48:55Z; 16:48:55, project automation — Verified | 2026-10-31T14:46:42Z; 16:46:42 — Inferred | No submitted human review; no approval | Open; merge/completion Unknown |
| [#240](https://github.com/melusi-k/ate-ios/pull/240) | 2026-10-31T14:51:06Z; 16:51:06 — Verified | 2026-10-31T14:51:08Z; 16:51:08, project automation — Verified | 2026-10-31T14:49:38Z; 16:49:38 — Inferred | No submitted human review; no approval | Open; merge/completion Unknown |
| [#241](https://github.com/melusi-k/ate-ios/pull/241) | 2026-10-31T15:03:41Z; 17:03:41 — Verified | 2026-10-31T15:03:42Z; 17:03:42, project automation — Verified | 2026-10-31T15:00:56Z; 17:00:56 — Inferred | No submitted human review; no approval | Open; merge/completion Unknown |
| [#243](https://github.com/melusi-k/ate-ios/pull/243) | 2026-10-31T17:10:26Z; 19:10:26 — Verified | 2026-10-31T17:10:28Z; 19:10:28, project automation — Verified | 2026-10-31T16:24:28Z; 18:24:28 — Inferred | No submitted human review; no approval | Merged 2026-10-31T19:25:07Z; 21:25:07 — Verified |
| [#244](https://github.com/melusi-k/ate-ios/pull/244) | 2026-10-31T19:28:44Z; 21:28:44 — Verified | 2026-10-31T19:28:46Z; 21:28:46, project automation — Verified | 2026-10-31T19:27:30Z; 21:27:30 — Inferred | No submitted human review; no approval | Merged 2026-10-31T22:16:50Z; 2026-11-01 00:16:50 — Verified |
| [#259](https://github.com/melusi-k/ate-ios/pull/259) | 2026-11-01T09:10:08Z; 11:10:08 — Verified | 2026-11-01T09:10:10Z; 11:10:10, project automation — Verified | 2026-11-01T09:09:57Z; 11:09:57 — Inferred | No submitted human review; no approval | Closed unmerged 2026-11-01T11:01:13Z; 13:01:13 — Verified |
| [#262](https://github.com/melusi-k/ate-ios/pull/262) | 2026-11-01T10:43:41Z; 12:43:41 — Verified | 2026-11-01T10:43:42Z; 12:43:42, project automation — Verified | Unknown — branch synchronization only | No submitted human review; no approval | Merged into #251 feature branch 2026-11-01T10:44:02Z; 12:44:02 — Verified; not merged to main |
| [#263](https://github.com/melusi-k/ate-ios/pull/263) | 2026-11-01T12:45:52Z; 14:45:52 — Verified | 2026-11-01T12:45:54Z; 14:45:54, project automation — Verified | 2026-11-01T12:44:57Z; 14:44:57 — Inferred | No submitted human review; no approval | Open draft; merge/completion Unknown |
| [#265](https://github.com/melusi-k/ate-ios/pull/265) | 2026-11-01T16:59:38Z; 18:59:38 — Verified | 2026-11-01T16:59:40Z; 18:59:40, project automation — Verified | Unknown — main-to-feature synchronization, not independent implementation | No submitted human review; no approval | Open; merge/completion Unknown |
| [#266](https://github.com/melusi-k/ate-ios/pull/266) | 2026-11-01T18:45:42Z; 20:45:42 — Verified | 2026-11-01T18:45:44Z; 20:45:44, project automation — Verified | 2026-11-01T18:45:08Z; 20:45:08 — Inferred | No submitted human review; no approval | Open; merge/completion Unknown |
| [#260](https://github.com/melusi-k/ate-ios/pull/260) | 2026-11-01T09:19:48Z; 11:19:48 — Verified | Not reconstructed here | Not calculated | No submitted human review; no approval | Merged 2026-11-01T16:47:25Z; 18:47:25 — Verified |
| [#261](https://github.com/melusi-k/ate-ios/pull/261) | 2026-11-01T10:01:26Z; 12:01:26 — Verified | Not reconstructed here | Not calculated | No submitted human review; no approval | Merged 2026-11-01T11:30:58Z; 13:30:58 — Verified |
| [#264](https://github.com/melusi-k/ate-ios/pull/264) | 2026-11-01T14:07:04Z; 16:07:04 — Verified | Not reconstructed here | Not calculated | No submitted human review; no approval | Merged 2026-11-01T15:48:13Z; 17:48:13 — Verified |

Existing lifecycle rows for #66, #181, #206, #231, #237, #238, #246, #247, #250, #251, #254, #255 and #234 remain in the 2026-11-01 addendum. PR #66's and #181's author COMMENTED reviews remain comments, not approvals. Bot/Codex comments are not human reviews. No first qualifying approval was found for the newly checked PRs above.

### Metrics and uncertainty

- Issue #242 created-to-closed lead time: **2h15m19s** (verified endpoints). Its implementation duration is not calculated because the earliest linked commit is only an inferred start.
- PR #243 opened-to-merged elapsed time: **2h14m41s**; PR #244: **2h48m06s**; PR #260: **7h27m37s**; PR #261: **1h29m32s**; PR #264: **1h41m09s**. These are PR metadata intervals, not implementation time or issue cycle time.
- No issue lead/cycle time is calculated for #30, #31, #70, #179, #245, #253, #138 or #195 because they remain open. No implementation duration is calculated from inferred earliest commits.
- No review/approval duration is calculable for the new PR set because no qualifying human approval was submitted. COMMENTED reviews and bot/Codex activity are not approvals.
- W44 commitment accuracy and carryover remain unavailable because the W44 committed-scope denominator was not recoverable. W45 metrics are not yet due; record outcomes at Sunday close-out only from the committed baseline and verified evidence.


## Lifecycle precision and planning-commit delta — 2026-11-02

This append-only correction supersedes the incomplete cells for PRs #260, #261 and #264 in the lifecycle table above; it does not alter their verified open/merge timestamps or rewrite earlier history.

- **Issue #179 first activity correction:** the first timeline event is a cross-reference at 2026-10-25T01:48:25Z (SAST 2026-10-25 03:48:25, Verified). The 2026-10-25T21:27:10Z referenced event recorded in the earlier W44 table is later activity, not the first activity. The earliest linked implementation commit remains 2026-10-25T06:40:40Z (SAST 08:40:40, Inferred).
- **PR #260:** opened 2026-11-01T09:19:48Z (SAST 11:19:48, Verified); first activity 09:19:50Z (SAST 11:19:50, project automation, Verified); earliest linked commit 09:17:58Z (SAST 11:17:58, Inferred); no submitted human review or approval; merged 16:47:25Z (SAST 18:47:25, Verified).
- **PR #261:** opened 2026-11-01T10:01:26Z (SAST 12:01:26, Verified); first activity 10:01:28Z (SAST 12:01:28, project automation, Verified); earliest linked commit 10:01:17Z (SAST 12:01:17, Inferred); no submitted human review or approval; merged 11:30:58Z (SAST 13:30:58, Verified).
- **PR #264:** opened 2026-11-01T14:07:04Z (SAST 16:07:04, Verified); first activity 14:07:05Z (SAST 16:07:05, project automation, Verified); earliest linked commit 14:05:53Z (SAST 16:05:53, Inferred); no submitted human review or approval; merged 15:48:13Z (SAST 17:48:13, Verified).
- No approval duration is calculated for these PRs because no qualifying human approval exists. Their merge timestamps are verified, but do not imply independent review or parent-issue completion.

The first W45 planning documentation commit is 51e046fffb02fb77d477a9a96922d19dc2c1e4c6, committed 2026-11-02T06:51:04Z (SAST 08:51:04). Its main-push Build IPA run [41402531733](https://github.com/melusi-k/ate-ios/actions/runs/41402531733) started 2026-11-02T06:51:07Z on that documentation-only SHA. This push follows the artifact-only main workflow; it is not full qualification and is not counted as release acceptance. Any later planning-document commit is likewise documentation-only unless a separate full-validation run proves otherwise.


## W45 Monday Guardian revalidation — 2026-11-02T09:16:44Z (SAST 2026-11-02 11:16:44)

**Evidence cutoff:** 2026-11-02T09:16:44Z / 2026-11-02 11:16:44 Africa/Johannesburg (UTC+02:00). This is an append-only Monday revalidation; prior W44/W45 dates and historical evidence above are preserved.

### W45 plan — current commitment and scope

- **Sprint:** 2026-W45, Monday 2026-11-02 through Sunday 2026-11-08.
- **Committed issue #30:** bounded release-readiness evidence refresh. Acceptance is a current-main exact-SHA gate ledger, truthful pass/fail/skipped/cancelled/missing classification, owner/dependency/next-action blockers, and a human go/no-go only after required evidence and signoff.
- **Committed issue #179:** bounded diary/goals follow-up, **at risk / entry-gated**, counted once as one issue-level outcome. Selected PR sequence: #239 root → #240 edit child → #241 weekly-totals child. PR records remain distinct from issue #179; child PRs are not separate throughput outcomes.
- **Stretch issue #70:** remains stretch only, with the existing planned window 2026-11-05 to 2026-11-08. No stretch work is started or promoted while #30/#179 committed work remains blocked. Do not broaden it into the full coverage-map audit.
- **Carryovers:** #181 and #66 remain stale drafts, not W45 commitments. #234 remains blocked. #251 and #254 remain uncommitted candidates. #263 and #266 are documentation/evidence candidates. #265 is a main-to-feature synchronization PR, not a product delivery.
- No new sprint dates are assigned to any other ticket. Existing planned dates are unchanged.

### Monday source review and backlog drift

Reviewed the unified backlog index, PRD, PRD gap register, MVP checklist, QA matrix, current main, all 42 open issue records and all 11 open PRs.

- `docs/PRD.md` implementation-audit banner and `docs/MVP_CHECKLIST.md` progress snapshot are dated 2026-10-24; `docs/PRODUCT_BACKLOG.md` still identifies itself as migration-in-progress as of 2026-10-22.
- The product-backlog Health/Journal index omits active issue #179 and #245; active Generation issue #253 is also absent from the index.
- `docs/PRD_GAP_REGISTER.md` records 176 intended IDs from its 2026-10-21 structural audit, while `docs/QA_MATRIX.md` reports 179 checklist IDs/rows. Do not silently change the denominator.
- The MVP/QA C-NUT-03 wording still says the verified catalogue is empty, while merged PR #238 added 30 source-traceable USDA SR Legacy records. Reconcile the actual records, source/version/provenance and usage-rights evidence before changing acceptance status; South African-source reuse rights remain unconfirmed.
- These are source-freshness/ownership findings for the wider #70 backlog. They do not expand the single bounded W45 stretch item or change any release gate, acceptance ID or denominator.

### Current main, release and governance

- Current `main`: `014bf30eec618059b1fba7e3830651ac4c3dd2a4` (commit timestamp 2026-11-02T06:53:15Z).
- Issue #33's Build IPA/readiness run [41402760851](https://github.com/melusi-k/ate-ios/actions/runs/41402760851) generated build 349 on this SHA. Wrapper/readiness success is not full qualification: unit, 8-flow QA, UI and backend-E2E were skipped; the disposition remains **BLOCKED: 1/59 verified, 12 failing, 46 open**, with QA-results retrieval HTTP 400.
- Exact-main Compile failed [run 41402795863](https://github.com/melusi-k/ate-ios/actions/runs/41402795863); Supabase Preview failed on the same SHA [run 41402760851](https://github.com/melusi-k/ate-ios/actions/runs/41402760851), check 125138144106. Open-state UI passed [41402795834](https://github.com/melusi-k/ate-ios/actions/runs/41402795834), but this does not replace full validation. No exact-main Dogfood Qualification pass is recorded.
- Main is unprotected (`protected=false`). Ruleset `main-production-protection` ID 26236404 exists with enforcement **disabled**. It configures one approving review, stale-review dismissal, thread resolution, strict `compile` and `dogfood-qualification` checks, but none is enforced while disabled. `.github/CODEOWNERS` contains only `* @melusi-k`; CODEOWNERS review and latest-push approval are both false. Squash is enabled; auto-merge and update-branch are disabled.
- Governance remediation: nominate an independent maintainer/team; enable the ruleset only after owner policy is valid; enforce independent approval, latest-push approval, CODEOWNERS review, resolved threads and strict required checks; enable supported update-branch or document a safe reviewed reconciliation path. No repository setting or policy was changed.

### Open PR status at Monday review

The 11-PR inventory was fetched before review. No PR satisfied all merge conditions; none was merged or branch-updated.

| PR | Relationship / divergence from current main | Exact-head evidence and decision |
|---|---|---|
| [#239](https://github.com/melusi-k/ate-ios/pull/239) | #179 root; 76 ahead / 28 behind | Dogfood passed; nutrition-focused 53-unit and 14-UI selections passed inside Compile, but overall Compile failed on CookingTrackerEntry, Cook Mode and CookIngredients regressions; open-state UI failed. No approval. Blocked. |
| [#240](https://github.com/melusi-k/ate-ios/pull/240) | #179 child 2/3; base is old #239 head; 65 ahead / 120 behind | Compile cancelled; no exact-head Dogfood. Non-mergeable/dirty; no approval. Blocked child. |
| [#241](https://github.com/melusi-k/ate-ios/pull/241) | #179 child 3/3; base is old #240 head; 64 ahead / 120 behind | Compile cancelled; no exact-head Dogfood. Diff removes diary-edit UI coverage and named pass guards; restore both. Blocked child. |
| [#251](https://github.com/melusi-k/ate-ios/pull/251) | Food Journal discovery candidate; 74 ahead / 28 behind | Compile failed; Dogfood, open-state UI and discovery UI passed. No approval. Not committed to W45. |
| [#254](https://github.com/melusi-k/ate-ios/pull/254) | Generation candidate; 22 ahead / 28 behind | Compile and open-state UI failed; Dogfood passed. On-device 11-fixture golden-set evaluation missing. No approval. Not committed. |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | QA scope proposal; 22 ahead / 161 behind; dirty | Compile failed; Dogfood passed. Still proposes `continue-on-error` for required #83 and unapproved A-SHARE-05 N/A/status changes. Blocked. |
| [#181](https://github.com/melusi-k/ate-ios/pull/181) | Old nutrition draft; 21 ahead / 401 behind; dirty | Compile/Dogfood missing; Supabase Preview skipped; three unresolved review threads; no approval. Draft carryover. |
| [#66](https://github.com/melusi-k/ate-ios/pull/66) | Old journal draft; 38 ahead / 753 behind; dirty | Compile/Dogfood missing; Supabase Preview skipped; one old P1 thread resolved/outdated; no approval. Draft carryover. |
| [#263](https://github.com/melusi-k/ate-ios/pull/263) | Draft evidence-only; 20 ahead / 28 behind | Docs validation passed; Compile skipped; Dogfood and open-state UI cancelled. Its manual evidence notes preserve result columns. Draft. |
| [#266](https://github.com/melusi-k/ate-ios/pull/266) | CI lifecycle documentation; 1 ahead / 2 behind | Docs validation passed; Compile skipped; Dogfood and open-state UI failed. No approval. Blocked. |
| [#265](https://github.com/melusi-k/ate-ios/pull/265) | Sync PR: head `main`, base `feat/issue-253-generation-pipeline`; 28 ahead / 24 behind relative to feature base | Not a product PR into main. Exact main head has failed Compile and Supabase Preview; release wrapper skipped required validation. No approval. Blocked synchronization request. |

No submitted human APPROVED review exists on any of the 11 open PRs. #181/#66 contain COMMENTED reviews only; Codex/bot comments are not human reviews. #181 has three unresolved threads; #66's sole thread is resolved/outdated; no review threads were returned for the other open PRs.

### Branch update and merge decisions

Repository metadata reports `allow_update_branch=false`; no supported update-branch action is exposed. No force-push, speculative merge commit, independent child rebase or unsafe branch rewrite was attempted. Manual maintainer reconciliation is required for #239/#251/#254/#266; #240/#241 must follow the root-to-leaf stack order. PR #265 is not a substitute for a supported update-branch action. No merge was attempted because the repository's main ruleset is disabled, there are no independent approvals, and exact-head required checks are failed, cancelled, skipped or missing.

### Lifecycle append — separate issue and PR timelines

All timestamps are exact UTC ISO-8601 with Africa/Johannesburg shown at UTC+02:00. **Verified** = GitHub metadata/timeline; **Inferred** = earliest linked implementation commit proxy; **Unknown** = no defensible evidence. These append to, and do not rewrite, prior lifecycle rows.

**Issue timelines**
- #30 created 2026-10-11T22:50:12Z (SAST 2026-10-12 00:50:12, Verified); first activity 2026-10-11T22:50:13Z (SAST 2026-10-12 00:50:13, Verified label event); actual work start Unknown; still open; completion Unknown.
- #179 created 2026-10-25T01:45:00Z (SAST 03:45:00, Verified); first activity 2026-10-25T01:48:25Z (SAST 03:48:25, Verified cross-reference); actual work-start proxy 2026-10-25T06:40:40Z (SAST 08:40:40, Inferred from earliest linked #181 commit); still open; completion Unknown.
- #70 created 2026-10-13T04:05:22Z (SAST 06:05:22, Verified); first activity 2026-10-21T10:37:09Z (SAST 12:37:09, Verified label event); actual work start Unknown; still open; completion Unknown.

**PR timelines**
- #239 opened 2026-10-31T14:48:54Z (SAST 16:48:54, Verified); first activity 14:48:55Z (16:48:55, Verified automation event); actual work-start proxy 14:46:42Z (16:46:42, Inferred earliest linked commit); no human review/approval; open, not merged.
- #240 opened 2026-10-31T14:51:06Z (SAST 16:51:06, Verified); first activity 14:51:08Z (16:51:08, Verified automation event); actual work-start proxy 14:49:38Z (16:49:38, Inferred); no human review/approval; open, not merged.
- #241 opened 2026-10-31T15:03:41Z (SAST 17:03:41, Verified); first activity 15:03:42Z (17:03:42, Verified automation event); actual work-start proxy 15:00:56Z (17:00:56, Inferred); no human review/approval; open, not merged.
- #263 opened 2026-11-01T12:45:52Z (SAST 14:45:52, Verified); first activity 12:45:54Z (14:45:54, Verified automation event); actual work-start proxy 12:44:57Z (14:44:57, Inferred); no human review/approval; draft/open.
- #265 opened 2026-11-01T16:59:38Z (SAST 18:59:38, Verified); first activity 16:59:40Z (18:59:40, Verified automation event); actual work start Unknown (main-to-feature synchronization does not establish implementation start); no human review/approval; open.
- #266 opened 2026-11-01T18:45:42Z (SAST 20:45:42, Verified); first activity 18:45:44Z (20:45:44, Verified automation event); actual work-start proxy 18:45:08Z (20:45:08, Inferred earliest linked commit); no human review/approval; open.
- No qualifying first substantive human review or approval is recorded for the open PR set. COMMENTED reviews and bot/Codex comments are not approvals. No PR merge or issue completion is inferred from these open records.

### Metrics and next actions

- No lead/cycle time is calculated for #30, #179 or #70 while they remain open. Implementation duration is not calculated from inferred commit proxies.
- No approval/review duration is calculable for the open PR set because no qualifying human approval exists. W45 commitment accuracy and carryover rate are not due until Sunday close-out; W44 denominators remain unavailable.
- Monday actions: keep #30 and #179 as the only committed outcomes; maintain the #239 → #240 → #241 order; fix main's failed Compile/Supabase and complete exact-SHA release gates; obtain independent review governance; keep all candidate/carryover work unscheduled unless the committed scope is accepted.


### W45 ISO-week boundary clarification — 2026-11-02

W45 is the full Monday–Sunday sprint **2026-11-02 through 2026-11-08**. Issue #70's pre-existing 2026-11-05 to 2026-11-08 dates are retained as a proposed late-week stretch execution window only; they are not the sprint start/end dates and do not create a separate sprint. This clarification preserves the original ticket dates and does not promote stretch work into the committed scope.


### Documentation PR #267 lifecycle and validation note — 2026-11-02

- PR #267 opened 2026-11-02T09:24:24Z (Africa/Johannesburg 2026-11-02 11:24:24, Verified); first activity is the PR-created event at the same timestamp (Verified); no independent human review or approval; draft/open, not merged.
- The initial `validate-stack` run failed because the PR-created event payload did not contain the required standalone `## Stack` metadata. The PR description was corrected to explicitly record Stack ID=None, Parent PR=None and Position=None. Rerunning the original workflow attempt still reads its original event payload; a new PR synchronize event is needed to validate the corrected description. This documentation PR remains a separate maintenance record and is not W45 product scope.


### PR #267 lifecycle precision — 2026-11-02

- PR opened: 2026-11-02T09:24:24Z (Africa/Johannesburg 2026-11-02 11:24:24, Verified).
- First activity: 2026-11-02T09:24:26Z (SAST 11:24:26, Verified project-automation event).
- Actual work-start proxy: 2026-11-02T09:24:14Z (SAST 11:24:14, Inferred from the earliest linked documentation commit; not a verified human start).
- First substantive human review: Unknown; approval: Unknown/no qualifying approval; merge: Unknown/not merged. PR remains draft. Its validation status is tracked in the PR conversation; skipped Compile/Supabase jobs are not passes.



## W45 Monday Guardian current-run delta — 2026-11-02 (12 open PRs)

**Evidence cutoff:** latest observed GitHub check event 2026-11-02T09:35:39Z (Africa/Johannesburg 2026-11-02 11:35:39, UTC+02:00). This is an append-only Monday planning refresh; the W44 close-out and earlier W45 plan remain unchanged.

### W45 scope decision

- **Sprint:** 2026-W45, Monday 2026-11-02 through Sunday 2026-11-08.
- **Committed #30:** bounded release-readiness evidence refresh, 2026-11-02 to 2026-11-08. Acceptance is a current-main exact-SHA gate ledger, truthful pass/fail/skipped/cancelled/missing classification, blocker ownership/dependencies/next actions, and human go/no-go only after required evidence and signoff.
- **Committed #179:** bounded diary/goals follow-up, at risk/entry-gated, 2026-11-02 to 2026-11-08. Retain one issue-level outcome through #239 root → #240 edit child → #241 weekly-totals child. No PR or child is counted as a separate delivery.
- **Stretch #70:** retain its previously recorded 2026-11-05 to 2026-11-08 late-week execution window; this is not the ISO-week boundary. Limit to one high-risk evidence/ownership mismatch. Do not promote stretch while #30/#179 remain blocked.
- **Carryovers:** #181 and #66; no new W45 dates.
- **Uncommitted candidates:** #251, #254, #263 and #266; no new W45 dates.
- **Blocked/not selected:** #234.
- **Branch synchronization only:** #265 (main → generation feature branch); not a product delivery.
- **Documentation maintenance:** #267; not a W45 product commitment.
- No scope or commitment status was changed in this refresh. Existing dates are preserved. The Wednesday 2026-11-04 checkpoint for #179 remains the de-scope trigger if root validation/reconciliation or child coverage is still blocked.

### Current product/backlog source review

The Monday review covered the product backlog, PRD, PRD gap register, MVP checklist, QA matrix, launch gates, current main, all 42 open issue records and all 12 open PRs.

- Current main: `014bf30eec618059b1fba7e3830651ac4c3dd2a4`.
- `docs/PRD.md` implementation-audit banner and `docs/MVP_CHECKLIST.md` progress snapshot are dated 2026-10-24; `docs/PRODUCT_BACKLOG.md` still identifies its migration status as 2026-10-22 and omits active issues #179, #245 and #253 from the Health/Journal/Generation index.
- The PRD gap register's structural inventory is 176, `docs/QA_MATRIX.md` reports 179 checklist IDs/rows, while `docs/LAUNCH_GATES.md` states 181 unique IDs. These are conflicting source counts; preserve all historical values and reconcile through #70 before changing a denominator.
- The MVP/QA C-NUT-03 catalogue wording still says the verified catalogue is empty, while merged PR #238 added 30 source-traceable USDA SR Legacy records. Verify the actual records, source/version/provenance and usage rights before changing the acceptance status. SAFOODS commercial reuse rights remain unconfirmed.
- These are bounded #70 stretch findings, not a reason to expand W45 committed scope or alter acceptance IDs, release-gate classes, denominators or CI policy.

### Current main and release evidence

- Issue #33 Build IPA/readiness [run 41402760851](https://github.com/melusi-k/ate-ios/actions/runs/41402760851) produced build 349 on the exact current main SHA. The generated disposition remains **BLOCKED: 1/59 verified, 12 failing, 46 open**; unit, 8-flow QA, UI and backend-E2E were skipped in that artifact workflow; QA-results retrieval returned HTTP 400.
- Exact-main Compile failed [run 41402795863](https://github.com/melusi-k/ate-ios/actions/runs/41402795863); open-state UI passed [run 41402795834](https://github.com/melusi-k/ate-ios/actions/runs/41402795834).
- Later QA-gate run [41421745685](https://github.com/melusi-k/ate-ios/actions/runs/41421745685) had `qa-gate` in progress at the latest poll; its backend-E2E job passed. This is not a complete QA-gate pass and does not supply a Dogfood pass.
- Supabase Preview failed on the same main SHA (check 125138144106 in [run 41402760851](https://github.com/melusi-k/ate-ios/actions/runs/41402760851)).
- No exact-main Dogfood Qualification pass is recorded. Release disposition remains **BLOCKED**.

### Current open PR inventory — 12 PRs

| PR | Relationship / branch comparison | Exact-head checks and disposition |
|---|---|---|
| [#239](https://github.com/melusi-k/ate-ios/pull/239) | #179 root; 76 ahead / 28 behind main | Dogfood passed; Compile failed (focused nutrition 53-unit/14-UI selections passed, overall shared regressions failed); open-state UI failed. No approval. Blocked. |
| [#240](https://github.com/melusi-k/ate-ios/pull/240) | #179 child 2/3; current #239 head vs child: 51 ahead / 154 behind | Compile cancelled; Supabase Preview skipped; no exact-head Dogfood or approval. Stale child. |
| [#241](https://github.com/melusi-k/ate-ios/pull/241) | #179 child 3/3; current #240 head vs child: 52 ahead / 53 behind | Compile cancelled; Supabase Preview skipped; no exact-head Dogfood. Diff removes named diary/edit pass-evidence guards; restore them. No approval. |
| [#251](https://github.com/melusi-k/ate-ios/pull/251) | Food Journal discovery candidate; 75 ahead / 28 behind main | Compile failed; Dogfood, open-state UI and discovery UI passed. No approval. Not committed. |
| [#254](https://github.com/melusi-k/ate-ios/pull/254) | Generation candidate; 24 ahead / 28 behind main | Compile and open-state UI failed; Dogfood passed. 11-fixture on-device golden-set evaluation missing. No approval. The prior `Closes #253` wording was corrected to a partial-scope relationship so this PR cannot prematurely close its parent issue. |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | QA scope proposal; 22 ahead / 161 behind main; dirty | Compile failed; Dogfood passed. Still proposes `continue-on-error` for required regression #83 and unapproved A-SHARE-05 N/A/status changes. Blocked. |
| [#181](https://github.com/melusi-k/ate-ios/pull/181) | Old nutrition draft; 21 ahead / 401 behind main; dirty | Compile/Dogfood missing; Supabase Preview skipped; 3 unresolved review threads (2 outdated, 1 current); no approval. Draft carryover. |
| [#66](https://github.com/melusi-k/ate-ios/pull/66) | Old journal draft; 38 ahead / 753 behind main; dirty | Compile/Dogfood missing; Supabase Preview skipped; sole review thread resolved/outdated; no approval. Draft carryover. |
| [#263](https://github.com/melusi-k/ate-ios/pull/263) | Draft evidence-only; 1 ahead / 25 behind main | Docs validation passed; Compile skipped; Dogfood and open-state UI cancelled. Draft. |
| [#265](https://github.com/melusi-k/ate-ios/pull/265) | Reverse sync: head main, base generation feature; 28 ahead / 24 behind relative to feature base | Current-main checks are not a dedicated PR qualification result. No approval. Synchronization only; not a PR into main. |
| [#266](https://github.com/melusi-k/ate-ios/pull/266) | CI lifecycle documentation; 3 ahead / 2 behind main | Docs validation passed; Compile skipped; Dogfood and open-state UI failed. No approval. Blocked. |
| [#267](https://github.com/melusi-k/ate-ios/pull/267) | This documentation PR; 4 ahead / 0 behind main at head 441fcc2 | Docs validation passed; Compile skipped; Dogfood and open-state UI were in progress at the latest poll. Draft; no independent approval. |

No submitted human APPROVED review exists on the 12 open PRs. COMMENTED reviews are not approvals; bot/Codex comments are not human reviews. No PR meets the merge criteria.

### Repository merge governance

- Main is unprotected (`protected=false`).
- Ruleset `main-production-protection` ID 26236404 exists with enforcement **disabled**. It configures one approval, stale-review dismissal, resolved review threads and strict `compile`/`dogfood-qualification` checks, but none is enforced while disabled.
- `.github/CODEOWNERS` contains only `* @melusi-k`; CODEOWNERS review and latest-push approval are false.
- Squash merge is enabled; auto-merge and update-branch are disabled.
- No independent approval exists. Do not merge automatically.
- Remediation: nominate an independent CODEOWNER; enable the ruleset only after ownership is valid; enforce independent approval/latest-push approval/CODEOWNERS review/thread resolution and strict checks; enable supported update-branch or document a reviewed manual reconciliation process. No repository policy was changed.

### Branch reconciliation and next actions

1. Reconcile #239 manually with current main; fix or validly rerun its failed shared regressions; rerun Compile and Dogfood on the resulting exact head.
2. After root acceptance, retarget/reconcile #240; after #240 acceptance, retarget/reconcile #241 and restore the removed edit-flow test/pass guards. Keep root-to-leaf order.
3. For #251/#254, manually reconcile to current main before rerunning their full exact-head gates; #254 also needs device golden-set evidence.
4. Keep #234 blocked until the #83 hard gate and QA scope are restored/explicitly approved.
5. Keep #181/#66 as carryovers pending distinct-scope/supersession decisions.
6. Keep #263/#266/#267 documentation/evidence PRs subject to their own checks and independent review; skipped app checks are not passes.
7. No force-push, speculative merge commit, branch update or merge was performed. GitHub update-branch is disabled.

### Metrics and retrospective schedule

- W44 close-out remains historical. Its committed-scope denominator was not recoverable, so W44 commitment accuracy and carryover rate remain unavailable.
- W45 commitment accuracy and carryover rate are not due until Sunday 2026-11-08 close-out.
- No lead/cycle time is calculated for open issues. No approval/review duration is calculable because there are no qualifying human approvals. Inferred earliest-commit proxies are not treated as verified work starts.
- This is Monday planning/revalidation, not a Sunday retrospective. No W45 completion or actual work start is inferred from the sprint start, ticket creation or PR creation.



### PR #267 post-refresh CI delta — 2026-11-02

The documentation update in this PR created prior head `b8a29ed78762543363e29b645762b7f6d2fcf364`. On that exact head, docs-validation passed [41423180766](https://github.com/melusi-k/ate-ios/actions/runs/41423180766) and stack validation passed [41423180783](https://github.com/melusi-k/ate-ios/actions/runs/41423180783); Compile and Supabase Preview were skipped; Dogfood Qualification [41423180812](https://github.com/melusi-k/ate-ios/actions/runs/41423180812) and open-state UI [41423180849](https://github.com/melusi-k/ate-ios/actions/runs/41423180849) were in progress at the latest poll. This append creates a new PR head, so those results are historical for the prior SHA; applicable checks must be rerun on the resulting head. No approval or merge is inferred.



### Lifecycle provenance corrections — 2026-11-02

The GitHub issue timeline API was re-read to resolve two earlier first-activity labels. These are append-only corrections; prior rows remain visible as historical records.

- **Issue #179:** earliest timeline event is the cross-reference to #180 at `2026-10-25T01:48:25Z` (Africa/Johannesburg `2026-10-25 03:48:25`, UTC+02:00) — **Verified**. The previously cited `2026-10-25T21:27:10Z` referenced-commit event is later activity, not first activity. Actual work-start proxy remains `2026-10-25T06:40:40Z` (SAST `08:40:40`) — **Inferred** from the earliest linked #181 commit, not a verified human start. Issue remains open; actual completion Unknown.
- **Issue #70:** earliest timeline event is the cross-reference to #30 at `2026-10-13T04:05:36Z` (Africa/Johannesburg `2026-10-13 06:05:36`, UTC+02:00) — **Verified**. The previously cited `2026-10-21T10:37:09Z` label event is later activity, not first activity. Actual work start remains **Unknown**; issue creation, sprint dates and ticket activity are not implementation-start evidence. Issue remains open; actual completion Unknown.

Before this append, PR #267 head `ab1e380ac396baa52f4aea413e66dbddc46fc263` had only a Supabase Preview **skipped** result visible; no docs-validation, stack-validation, Dogfood or open-state result was present on that exact SHA. This append changes the PR head, so all prior-head results remain historical and the applicable checks must run again on the new head.


## W45 Tuesday Guardian delivery revalidation — 2026-11-03T09:42:12Z (Africa/Johannesburg 2026-11-03 11:42:12, UTC+02:00)

**Sprint:** 2026-W45, Monday 2026-11-02 through Sunday 2026-11-08. This is a Tuesday delivery/status revalidation, not a retrospective or replanning event. Existing planned dates and commitment statuses are preserved.

### Current main and release evidence

- Current `main`: `80ccac65859b643ead2777127c4815777a813c23`, merged 2026-11-02T23:28:35Z.
- Build IPA/readiness [run 41545716878](https://github.com/melusi-k/ate-ios/actions/runs/41545716878) generated build 352 on that SHA. Disposition: **BLOCKED — 1/59 verified, 12 failing, 46 open**; unit, 8-flow QA, UI and backend-E2E were skipped; QA-results retrieval returned HTTP 400.
- Main Compile Check passed [run 41546204436](https://github.com/melusi-k/ate-ios/actions/runs/41546204436); Journal open-state UI failed [run 41546204187](https://github.com/melusi-k/ate-ios/actions/runs/41546204187). No Dogfood Qualification run is recorded on this main SHA. A Compile pass and artifact build do not establish release readiness.

### W45 commitment and selected records

- **Committed #30:** bounded release-readiness evidence refresh; remains open and BLOCKED. Its issue body now records the current-main Build 352 evidence and governance dependency.
- **Committed #179:** one at-risk/entry-gated nutrition outcome, counted once. Its issue body and PR bodies now record the current stack state:
  - [#239 root](https://github.com/melusi-k/ate-ios/pull/239): head `308cf71078a09911d70abe7f00bafd4b987a761c`, 76 ahead / 38 behind main; Dogfood passed [41307451102](https://github.com/melusi-k/ate-ios/actions/runs/41307451102), Compile failed [41307451114](https://github.com/melusi-k/ate-ios/actions/runs/41307451114), Journal open-state UI failed [41307451213](https://github.com/melusi-k/ate-ios/actions/runs/41307451213).
  - [#240 edit child](https://github.com/melusi-k/ate-ios/pull/240): base still points to old #239 SHA `03c6725ef375d3cc1b219ed066c38939e204442b`, not current root `308cf71078a09911d70abe7f00bafd4b987a761c`; 51 ahead / 154 behind current parent; Compile [41259962103](https://github.com/melusi-k/ate-ios/actions/runs/41259962103) cancelled; no exact-head Dogfood.
  - [#241 weekly-totals child](https://github.com/melusi-k/ate-ios/pull/241): base still points to old #240 SHA `f20f7a83381685e7a8a8b7e2cd52a903c174534a`, not current parent `98f71aad2c75ac361cf3dcff18e79c84dce1b3f4`; 52 ahead / 53 behind current parent; no exact-head Compile/Dogfood, and prior Compile [41260002276](https://github.com/melusi-k/ate-ios/actions/runs/41260002276) was cancelled. Restore the removed edit-flow pass-evidence guards and retain the UI acceptance test.
- **Stretch #70:** remains Stretch only, with its existing 2026-11-05 to 2026-11-08 proposed execution window. No stretch work is started or promoted while #30/#179 remain blocked. The issue body records this explicitly.
- No other ticket received W45 dates. The three nutrition PRs remain separate PR lifecycle records and one issue-level outcome.

### Open PR inventory — 2026-11-03

17 open PRs were fetched before review. No PR was merged, no branch was rewritten, and no repository settings or merge policies were changed.

| PR | Current disposition / evidence |
|---|---|
| [#239](https://github.com/melusi-k/ate-ios/pull/239) | Blocked root: Compile and Journal open-state UI failed; Dogfood passed; 76 ahead / 38 behind main. |
| [#240](https://github.com/melusi-k/ate-ios/pull/240) | Blocked stacked child: stale base vs #239, 51 ahead / 154 behind current parent; Compile cancelled; no Dogfood. |
| [#241](https://github.com/melusi-k/ate-ios/pull/241) | Blocked stacked child: stale base vs #240, 52 ahead / 53 behind current parent; no exact-head Compile/Dogfood; removed edit pass guards. |
| [#251](https://github.com/melusi-k/ate-ios/pull/251) | Uncommitted #245 candidate: Compile failed; Dogfood, Journal open-state UI and discovery UI passed; 75 ahead / 38 behind main. |
| [#254](https://github.com/melusi-k/ate-ios/pull/254) | Uncommitted #253 partial/eval-gated slice: Compile and Journal open-state UI failed; Dogfood passed; 24 ahead / 38 behind main; 11-fixture device golden-set evaluation missing. |
| [#234](https://github.com/melusi-k/ate-ios/pull/234) | Blocked: Compile failed, Dogfood passed, 22 ahead / 171 behind; diff still weakens required regression #83 with `continue-on-error` and changes acceptance scope without qualifying approval. |
| [#270](https://github.com/melusi-k/ate-ios/pull/270) | Candidate navigation-audit test: Compile and Dogfood passed; Journal open-state UI failed; 1 ahead / 8 behind main. |
| [#268](https://github.com/melusi-k/ate-ios/pull/268) | Diagnostics-only change: Compile and Dogfood failed; Journal open-state UI passed; 1 ahead / 10 behind main. |
| [#266](https://github.com/melusi-k/ate-ios/pull/266) | Documentation-only CI lifecycle record: Compile passed, Dogfood and Journal open-state UI failed; 3 ahead / 12 behind main. |
| [#267](https://github.com/melusi-k/ate-ios/pull/267) | Draft W45 documentation proposal: prior head `4e8cfcbcc0f7130041d13c68db2af802971fdb6e` had Compile, Dogfood, Journal open-state UI and stack validation pass; branch was 7 ahead / 10 behind main. This Tuesday append creates a new head; prior-head checks are historical and must be rerun. |
| [#263](https://github.com/melusi-k/ate-ios/pull/263) | Draft evidence-only QA-matrix change: Compile passed; Dogfood and Journal open-state UI were cancelled; 1 ahead / 35 behind main. |
| [#272](https://github.com/melusi-k/ate-ios/pull/272) | New #245 timeline-logic slice: Compile and Dogfood passed; Journal open-state UI failed; 2 ahead / 2 behind main. No human review/approval. |
| [#275](https://github.com/melusi-k/ate-ios/pull/275) | New #245 store-snapshot child of #272: Compile in progress, Journal open-state UI failed, no Dogfood on this exact head. Parent #272 is not accepted. |
| [#274](https://github.com/melusi-k/ate-ios/pull/274) | Reverse-direction sync PR from main into #272's feature branch; Compile passed on main, Journal open-state UI failed. Its checks do not qualify the merged feature tree. |
| [#265](https://github.com/melusi-k/ate-ios/pull/265) | Reverse-direction sync PR from main into the generation feature branch; main Compile passed, Journal open-state UI failed; no Dogfood qualification of the merged feature tree. |
| [#181](https://github.com/melusi-k/ate-ios/pull/181) | Draft stale nutrition foundation: 21 ahead / 411 behind main, no exact-head Compile/Dogfood, three unresolved review threads including corrupt-goals recovery. |
| [#66](https://github.com/melusi-k/ate-ios/pull/66) | Draft stale journal acceptance: 38 ahead / 763 behind main, no exact-head Compile/Dogfood; one resolved/outdated inline thread. |

No open PR has a qualifying human approval. Submitted `COMMENTED` reviews and Codex bot comments are not approvals. PR #181 retains three unresolved inline threads; #66's one inline thread is resolved/outdated. Codex review attempts on newer PRs could not complete because the configured service reported usage limits; this is not a review pass.

### Repository merge governance

Live configuration on 2026-11-03:

- Branch `main`: `protected=false`; branch-protection `enabled=false`.
- Ruleset [main-production-protection](https://github.com/melusi-k/ate-ios/rules/26236404): enforcement **disabled**.
- Ruleset configures one approving review, stale-review dismissal, latest-push approval false, review-thread resolution, strict `compile` and `dogfood-qualification` checks; these controls are not enforced while the ruleset is disabled.
- `.github/CODEOWNERS`: `* @melusi-k`; `require_code_owner_review=false`. The only owner is the repository author, so independent ownership must be nominated before requiring CODEOWNERS approval.
- Squash merge is enabled; auto-merge and GitHub update-branch are disabled.

Recommended remediation remains: nominate an independent maintainer/team, enable the reviewed ruleset with required checks and independent approval/latest-push/CODEOWNERS/thread-resolution rules, and enable supported branch updates or document a safe manual process. No governance settings were changed.

### Lifecycle and metrics

Issue #30/#179/#70 lifecycle timestamps and confidence labels are unchanged by this Tuesday status run. PR #272 was opened 2026-11-02T21:28:59Z (SAST 23:28:59); PR #275 was opened 2026-11-03T08:54:51Z (SAST 10:54:51). Their PR-specific first activity, commit-based work-start evidence and confidence labels must remain separate from issue #245. No PR merge, approval, issue closure or actual completion is inferred.

W44 commitment accuracy/carryover and W45 completion metrics remain unavailable until a committed-scope denominator and Sunday outcomes exist. Lead/cycle/review/approval durations are not calculated from missing endpoints. No retrospective is performed on Tuesday.

### Actions and limitations

- Updated the W45 Tuesday status blocks on issues #30, #179 and #70 and appended matching status to selected PR bodies #239–#241.
- The new Tuesday record is appended on the existing draft documentation branch for PR #267, not on main. The branch is stale against current main and GitHub update-branch is disabled; a maintainer must reconcile it safely and all applicable checks must rerun on the new SHA.
- No PR was merged, no application branch was rewritten, no issue was closed, no sprint commitment/date was changed, and no repository policy was modified.


### PR #267 exact-head check poll correction — 2026-11-03T09:42:12Z

The Tuesday append created PR #267 head `ea0afbcf0f3dd4f832a5e3995ab045a7a313aadc`. The first poll after that commit showed Compile passed [run 41614377568](https://github.com/melusi-k/ate-ios/actions/runs/41614377568) and stacked validation passed [run 41614377649](https://github.com/melusi-k/ate-ios/actions/runs/41614377649); Dogfood Qualification [run 41614377537](https://github.com/melusi-k/ate-ios/actions/runs/41614377537) and Journal open-state UI [run 41614377628](https://github.com/melusi-k/ate-ios/actions/runs/41614377628) were still in progress. No approval or merge is inferred. The branch remains 8 commits ahead / 10 behind current main and draft. These are exact-head results for this documentation SHA only; any subsequent commit requires fresh validation.


### PR #267 exact-head poll correction — 2026-11-03T09:53Z (Africa/Johannesburg 2026-11-03 11:53 SAST)

The prior exact head `aa15700ecbd5746016cabcd915865ab344a55fbc` now has:
- docs-validation passed [run 41614643407](https://github.com/melusi-k/ate-ios/actions/runs/41614643407);
- Compile was **skipped** by the docs-only path (same run);
- stacked validation passed [run 41614669519](https://github.com/melusi-k/ate-ios/actions/runs/41614669519);
- Dogfood Qualification [run 41614643596](https://github.com/melusi-k/ate-ios/actions/runs/41614643596) remained pending;
- Journal open-state UI [run 41614643482](https://github.com/melusi-k/ate-ios/actions/runs/41614643482) remained in progress;
- Supabase Preview was skipped.

This poll corrects the earlier "no runs visible" note for `aa15700`; it does not establish a green result for the pending/in-progress checks. This append creates another documentation head, so the above results remain evidence for `aa15700` only and all applicable checks must run again on the new SHA. The PR remains draft and the branch remains behind current main; no merge or approval is implied.
