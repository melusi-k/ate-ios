# Launch gates and scoring

How Pilot and Public launch readiness is scored. Acceptance IDs and criteria live in [MVP_CHECKLIST.md](MVP_CHECKLIST.md); per-ID results live in [QA_MATRIX.md](QA_MATRIX.md). [MVP_SCORE.md](MVP_SCORE.md) keeps the build-36 history only.

Sections marked **Repo policy** restate rules already in MVP_SCORE.md. Sections marked **Proposed** are new and need the owner's decision before they count.

## 1. Gates and denominators (repo policy, counts from the matrix)

| Gate | QA_MATRIX `Release gate` | Rows |
|---|---|---:|
| Pilot (internal beta) | `Pilot` (was Tier A) | 97 |
| Public launch | `Public launch` (was Tier B), plus every Pilot row must still hold | 13 |
| Not scored | `No committed release gate` (was Tier C) | 69 |
| Total acceptance IDs | | 179 |

The matrix and checklist both contain 179 unique IDs. Earlier text said 176; that was stale and is corrected here. `scripts/check-ids.py` should assert the checklist and matrix ID sets are identical and that the gate counts above match, so the numbers cannot drift.

The 59-item tally printed by `scripts/release/readiness.py` is a different measure: it counts items in the release-readiness issue template, each mapped to one or more acceptance IDs or CI jobs. It is a summary for the release issue, not the gate score. Gate scores use acceptance IDs only.

## 2. Per-row result (repo policy)

A row passes only with evidence on the exact candidate commit SHA. Every other state scores 0 and is reported under its own name, never merged into "fail":

| State | Meaning | Points |
|---|---|---:|
| Pass | All required automated and device/manual checks recorded for this SHA | 1 |
| Failed | A recorded check ran and the app did not meet the criterion | 0 |
| Blocked | Cannot run (missing account, hardware, backend) | 0 |
| Not run / Skipped / Quarantined | No evidence for this SHA | 0 |
| Partial | Some required checks passed, others missing | 0 |

"Not verified" is not "broken". Reports must show Failed separately from Not run so the app is not described as failing where it is only unproven. Note that in the current matrix the ❌ icon means "not done" and can hide either case; split it into Failed vs Not run when reconciling.

## 3. n/a rules (proposed)

A row leaves the denominator only if listed in a table in this file with: the ID, the reason, the date, and who approved it. At most these may be n/a: rows whose criterion no longer applies to the shipped product. A row that is merely hard to test, blocked, or deferred is never n/a. Reports print the n/a list and its size next to the score.

## 4. Gate pass conditions

Repo policy: explicit gates decide the release, not an aggregate percentage; device and production checks stay separate from simulator/CI.

Proposed, to be confirmed by the owner:

1. **Must-pass rows: 100% Pass.** Pilot: A-AUTH-01 to A-AUTH-09 (A-AUTH-09 on a real device) and A-SHARE-01 to A-SHARE-05. Public launch: those plus B-SHARE-01. These are the "launch gate" groups already named in PRD_GAP_REGISTER.md and the build-36 checklist legend.
2. **No Failed row in the gate.** Any Failed row blocks the gate.
3. **Coverage threshold (owner picks A or B).**
   - **Option A:** Pilot: at least 90% of the 97 Pilot rows Pass. Public: all 13 Public rows Pass and at least 95% of Pilot rows Pass. Rows that do not pass stay listed as not passed, each with a written note signed by the owner. A note is a record, not a pass.
   - **Option B:** strict 100% Pass of the gate's rows (Public also needs 100% of Pilot rows). No waiver counts toward a passed gate.
4. **Required jobs ran.** Unit, QA 8-flow, UI and E2E jobs executed on the SHA. If any were skipped the gate state is "Not scored".
5. **Human decision.** Release decision and final signoff are recorded by the owner; tooling only suggests. Releasing despite an unmet gate is allowed only as an explicitly recorded release decision that names the unmet rows. The gate still reads "not passed".

Rationale for Option A: 90% of 97 allows at most 9 non-passing Pilot rows, each visible and signed, for a small internal pilot where testers know the build is early. Public is stricter because real users and universal links are involved. These numbers are judgement, not derived from repo data. Option B is the strict alternative. Moving a row to "No committed release gate" is scope deferral, not a waiver and not evidence the row is ready; any moved rows must be listed in the report and the gate must not be described as fully passed because of them.

## 5. Reporting format

Per gate, always print all of: Pass / Failed / Blocked / Not run (incl. Skipped, Quarantined, Partial) / n/a, the denominator, open must-pass IDs, the SHA, and which jobs ran. Show "x of N Pass" and do not print a bare percentage. Until every row in the gate has been reconciled on one SHA, state "not yet scored".
