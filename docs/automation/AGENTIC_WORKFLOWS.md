# Agentic workflow preparation (inactive)

Eight additive gh-aw sources and compiler-generated locks, compiled with
checksum-verified gh-aw v1.2.2. No workflow has been dispatched or activated.
The top-level `if: "false"` compiles to false activation (literal false or an AND false command guard); dependent inference
and output jobs skip. `safe-outputs.staged: true` is a second output-only safety
layer, not a way to make inference free. Do not remove either in this packet.

## Prepared behavior and UTC schedule

| Source | Intended behavior after separately reviewed activation | Cadence |
| --- | --- | --- |
| aw-ci-diagnosis | Read recent current default/open-PR-head CI failures, compare logs, one novel diagnosis issue, search all open incidents before creating | Every6hours at minute29 |
| aw-repository-assistant | New-issue label/comment triage, bounded pure-logic bug fix, max1 labelled draft PR, no closing or merge | 04:17/12:17/20:17 |
| aw-daily-report | Last24hours repository activity issue; date-key dedup and close-older only for this report workflow | 05:23 daily |
| aw-focused-tests | User-intent-focused tests only in explicit allowed test files, max1 labelled draft PR | 06:41 daily |
| aw-daily-plan | One UTC-date priorities issue, exact published PO morning ranking within MVP/Pilot/Launch, own-report close-older only | 05:47 daily |
| aw-grumpy-reviewer | On-demand /grumpy on same-repo PR comment; max1 COMMENT advisory, max3 findings, max3 reviews/PR, once/head best effort | No schedule |
| aw-ci-coach | Evidence-backed compatible cache/setup overhead draft proposal, immutable qualification/test/stall/runner/evidence policy | 09:11 daily |
| aw-doc-updater | Last24hours merged-code documentation gaps, allowed usage/implementation docs only, max1 labelled draft PR | 07:53 daily |

The four PR-producing workflows are EXEMPT from the ordinary10 active-PR cap;
max1/run, drafts, labelled, never auto-merged. Reviewer remains the only merger.
No skip-at10 rule. Doc-updater creation was confirmed after the initial link-only
interpretation; none of these requests authorizes activation or inference spend.

## Source constraints and safety

Agent GitHub permissions read-only, custom read token fixed to GITHUB_TOKEN,
issue/PR mutations only through declared safe outputs. Scope excludes Journal,
Health, Food Journal activation/account/reset/sync/server/workflow edits. Explicit
path allowlists constrain patches, not only natural-language instructions. Triage
can add only existing allowlisted type labels, max1 target/run; it cannot change
gates/priorities or close issues. All outputs are staged in this packet. Threat
detection remains enabled, not bypassed. No pull_request/workflow_run triggers,
CI reruns, dispatches, paid/custom runners, provider web access or dependencies.
Narrow shell-command list is defense in depth, not a proof that allowed commands
cannot execute arbitrary code. Logs/issues/PRs remain untrusted data.

Dedupe uses current GitHub issue/PR/commit records rather than a new memory branch.
It is best-effort, not atomic exactly-once. Daily reports close older matching
report outputs, not incidents or product issues. No native quality/coverage claim
comes from compilation or the creation of a test file. Ubuntu has no iOS simulator;
XCTest must be marked NOT RUN until normal Reviewer-arranged native checks pass.

GITHUB_TOKEN-created PRs ordinarily do not trigger CI. The packet explicitly sets
`github-token-for-extra-empty-commit: none`; it does not read the magic CI token
or arrange a PAT/App bypass. Reviewer must arrange supported ordinary exact-head
qualification before accepting/merging. Existing CI/rulesets remain unchanged.

## Activation prerequisites and costs (unresolved)

1. Main sources now choose Pi with exact Google model IDs: Flash-Lite3.1 for
   daily report/plan/CI diagnosis, Flash3.6 for other workflows. Main and detection
   both explicitly reference GEMINI_API_KEY in their own engine.env. No key was
   created, read, stored or used here. No billing or inference was activated.
   BLOCKER: gh-aw v1.2.2 accepts detection.engine.id: pi in source but compiles
   it to `threat-detect --engine copilot`, COPILOT_MODEL and COPILOT_GITHUB_TOKEN.
   Its own warning confirms Pi detection still uses Copilot CLI. Therefore a
   Gemini key alone is NOT sufficient. Detection is enabled, never bypassed.
   Wait for supported Google-backed detection before activation; don't silently
   switch to Copilot billing, disable detection or hand-edit generated locks.
2. Standard public-repository Ubuntu Actions usage can be free, but AI inference
   is separate. Compiler defaults include nonzero AI-credit limits; those are not
   a zero-dollar guarantee. Detection also uses inference. No model execution
   was used to validate this packet. If zero-spend cannot be verified, keep OFF.
3. Verify GitHub Actions settings allow safe-output draft PR creation; verify
   labels agentic-assistant, agentic-tests, agentic-docs and agentic-ci-coach exist. No labels or
   repository settings were created/changed. Enable any needed permission only
   under separate review. No inference credential is a repository-write grant.
4. Review allowed scope/schedules. Recompile after edits, inspect all generated
   jobs/permissions, then separately approve activation and unstage outputs. A
   live smoke test, notification/dedup behavior and PR/issue effects remain NOT RUN.

## Validation and known limits

Eight strict compiles succeed; all locks report compiled Yes. Static checks verify
activation=false, agent read-only, Ubuntu-only jobs, staged outputs and no
GH_AW_CI_TRIGGER_TOKEN in locks. Python185 tests pass with all eight sources; these tests do not exercise gh-aw live behavior. diffcheck passes.
Six compiler warnings are fixed-time schedule recommendations, not errors.
Compiler emits large locks (roughly2200lines each) and an action-pin cache;
only sources, generated locks, .gitattributes and this notes file are intended
for review. No installed binary, raw repository logs or credentials are included.
The newest main authoring guide's `max-bot-mentions:0` is rejected by v1.2.2;
that option is omitted, mentions disabled, prompt prohibits bot/closing triggers.

## References actually read

- https://raw.githubusercontent.com/github/gh-aw/main/create.md
- https://raw.githubusercontent.com/github/gh-aw/main/.github/aw/create-agentic-workflow.md
- https://github.github.com/gh-aw/reference/auth/
- https://github.github.com/gh-aw/reference/engines/
- https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions
- https://github.com/githubnext/agentics/blob/main/docs/doc-updater.md
- https://github.com/githubnext/agentics/blob/main/docs/repo-assist.md
- https://github.com/githubnext/agentics/blob/main/docs/ci-coach.md

Upstream main guidance is mutable. Revalidate current auth/cost/tool semantics at
activation, not from this preparation record. This document grants no permission.

## Repo Assist adaptation

The owner-supplied Repo Assist reference supplies investigation-first behavior,
minimal surgical fixes, Test Status and anti-repeat/contributor conventions. This
bounded adaptation deliberately omits upstream weighted task selection, commands,
repo-memory branch, eight-PR cap/four-PR batches, updates of existing PR branches,
monthly issue, dependency/CI/release work and broad forward-feature work. The
separate daily report handles visibility. Max1 labelled DRAFT/run and cap exemption
are local requirements. Missing/incomplete diagnostic issue creation is disabled,
not merely staged. Compiler still emits issues:write on the system conclusion
job even with both diagnostic create-issue environment flags false. This is a
known excess permission to re-review at activation, not read-only across ALL jobs.
The agent itself remains read-only. Hard activation:false skips the conclusion
job in ordinary inactive runs; do not rely on staging alone for system diagnostics.

## CI Coach adaptation

Additive sixth workflow from the owner's link, inactive. Evidence compares failures
and passes across comparable heads, maps CI lifecycle stages and existing turnaround
work. Only compatible cache/non-test setup overhead proposals in compile-check and
dogfood workflows are eligible; every gate/test/runner/stall/timeout/cancellation/
artifact-retention field is immutable. Sensitive workflow patches use request-review
handling; never bypass that review. Max1 labelled DRAFT/run, cap-exempt. Measured
proposal docs are the fallback when runtime equivalence cannot be shown. No test
removal, trigger filtering, new lanes, paid runners or before/after speedup claim
without actual candidate proof. Scope does not include all repository workflows.


### Existing CI ownership, not a new backlog

CI Coach is the automation vehicle for build/CI turnaround, repeated qualification
failures, Simulator launch reliability and centralized lifecycle evidence. Current
open anchors verified 12November2026:
- https://github.com/melusi-k/ate-ios/issues/78 (CI/workflow operations)
- https://github.com/melusi-k/ate-ios/issues/138 (CI resilience audit)

Each future PR links the live relevant issue/outcome and uses agentic-ci-coach,
ci and area:product-infrastructure labels. No issue creation/closing/reassignment
or new roadmap. Source runtime reliability fixes still belong to their feature
owners. Alongside bounded cache/setup edits, measured reliability evidence and
append-only dated lifecycle entries are eligible; no unproven causal assertion,
rewritten history or policy relaxation. The four existing CI outcome todos stay
open until their own actual result is delivered, not completed by this workflow.

## Grumpy advisory review adaptation

Source: https://github.com/githubnext/agentics/blob/main/docs/grumpy-reviewer.md
On-demand PR-comment command only, no automatic every-PR flood. Full PR/diff/review
history read without running PR code. Source config permits COMMENT only, max1,
no inline/add-comment outputs. Preconditions skip held/mixed held areas, forks,
drafts, closed PRs, over40/incomplete diffs, repeated head or third prior advisory.
Max3 high-confidence findings/body. History dedup is best-effort, not exactly-once.
This review never counts as the required independent Reviewer, even if clean.
No APPROVE/REQUEST_CHANGES output is available; upstream verdict behavior omitted.
Still inactive/staged and subject to same unresolved engine/zero-spend conditions.

### CI Coach workflow-edit prerequisite

Current GITHUB_TOKEN cannot push changes to .github/workflows. Safe-output workflow
edits additionally require allow-workflows:true plus a separately scoped GitHub
App. Neither is configured or approved here; do NOT treat the two-file allowlist
as proof that those patches can publish. Until separately reviewed authority and
capability exist, CI Coach must produce docs-only measured optimization/reliability
proposals. No extra write permission/secret/trigger added to bypass this limitation.

Slash-command compiler caveat: Grumpy pre_activation and activation conditions
both include AND(false), so remain inactive. Its compiler-generated activation job
also declares issues/pull-requests write for command-event plumbing even with
status-comment:false. This is not agent write access but must be re-reviewed
before activation, alongside the shared system conclusion issues:write caveat.
Do not describe every generated job as read-only or source compilation as proof
that runtime dedup/held-area detection is unbypassable. Only the review EVENT
allowlist is structural COMMENT-only; eligibility/history checks are pre-read
facts plus agent instructions and need smoke validation before activation.

## Daily Plan adaptation (8th workflow)

Source: https://github.com/githubnext/agentics/blob/main/docs/plan.md
The initial local /plan task-list interpretation was corrected before delivery:
actual upstream is DAILY team-priority planning issue creation/update. This eighth
workflow follows that upstream shape: one daily issue, replacing only its own
prior dated plans. No /plan trigger, task/subissue creation, assignments, source
issue closure/reprioritization or gate moves. Daily Plan is separate from the
activity report. MVP => Pilot => Launch, preserve PO morning ranking within each.
Current-main date-stamped PO ranking must be published first; absent/stale/conflicting
ranking means noop/report_incomplete rather than fabricated priority decisions.
Private PO chat isn't a GitHub input. No automatic acceptance ticks. Dedup searches
open/closed same-day keys. Compilation is not execution, activation or zero-cost
inference approval. Same dormant/staged and engine/credential caveats apply.

## Pi source preparation14November2026, execution blocked

Latest published compiler confirmed v1.2.2 on14November2026:
https://github.com/github/gh-aw/releases/tag/v1.2.2 . All eight strict compiles
succeed but each warns that Pi threat detection needs Copilot authentication.
Generated main runtime routes `GH_AW_LLM_PROVIDER=google` and GEMINI_API_KEY;
generated detection uses Copilot, despite metadata reporting Pi. Metadata alone
is not acceptance. `network.allowed: []` retained; compile success is not live
endpoint reachability evidence. No API/model invocation, activation or spend.

Security review: sole new restricted secret name GEMINI_API_KEY. It is referenced
only in provider/detector environment, with no authored output or shell echo.
No new authored action, output permissions, path allowances or redirect. All
activation false guards, staged outputs, detection and schedules remain intact.
Compiler-generated action/container pins may be refreshed by its pin resolver;
review generated diff separately. No credential value is present in this packet.
Free-only project/no-billing and exact gateway inventory remain activation checks.

References inspected:
- https://github.github.com/gh-aw/reference/engines/pi/
- https://github.github.com/gh-aw/reference/threat-detection/
- https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite?authuser=2
- https://ai.google.dev/gemini-api/docs/pricing?authuser=002
