# Design review above existing delivery gates

Status: Proposed, draft adoption. No change to CI, release policy or permission to implement.

This process adds design checks to the Plan/Build boundary in [PRODUCT_LIFECYCLE.md](../PRODUCT_LIFECYCLE.md). It does not replace that lifecycle, [stack review](STACKED_PULL_REQUESTS.md), the QA matrix, exact-candidate verification or human release decisions. A clean design review is not compile, test, model-quality or physical-device evidence.

## When to use it

Use a design document before substantial cross-domain work, persistence/migration changes, new model/context access, system actions, privacy/security boundaries or irreversible operations. Apply a focused review to a local change when its risk warrants one.

Do not require the full process for typos, a small isolated fix, routine dependency bumps or formatting. Their existing review/tests still apply. An apparently small dependency change that changes a security or data boundary is not exempt merely because its diff is short.

## Adopted practices and limits

| Practice | Ate use |
| --- | --- |
| Brainstorm | State problem, evidence, goals/non-goals and alternatives. Reuse the owning issue; do not invent product decisions. |
| Draft | Use [the design template](architecture/DESIGN_TEMPLATE.md). Separate high-level architecture from implementation steps. |
| Review | Run the five stages below before substantial implementation. |
| Resolve | Record each finding's evidence, proposed disposition and human decision. |
| Drift report | Compare named documents against a named source revision; record differences and coverage limits, not a blanket clean bill. |
| Review-loop | Select architecture, security/data integrity and readiness lenses as needed. Default pilot budget: two review rounds, then stop with open findings for human decision. No automatic paid service or resource expansion. |
| Bootstrap | First find real documentation gaps. Add a bounded source/ownership map where missing. No recursive README generation or replacement of existing documents. |

The initial pilot is [Intelligence Foundation](architecture/ATE_INTELLIGENCE_FOUNDATION.md), subordinate to current release gates. Scope and review cost should be stated before starting. Two clean rounds may support confidence, but are not proof of correctness. A failed, missing or timed-out review is recorded as not run, not zero findings. Fresh-context review aims to reduce shared assumptions; isolation or independence is not guaranteed merely by a fresh review label.

## Five design stages

1. Initial architecture challenge: can existing domain services solve this with less new structure?
2. Comprehension: can a reader explain the design from the document alone? Record the paraphrase and gaps.
3. Technical critique: inspect failure, cancellation, privacy, data integrity, migration and unsupported-device paths.
4. Second simplicity review: did the fixes add avoidable complexity?
5. Implementation readiness: are file boundaries, interfaces, dependencies, negative tests, rollout and remaining decisions precise enough?

Review against an exact document revision and declared reading list. Re-review material edits. Preserve raw findings and their consolidated IDs without implying every lens ran. Do not claim a stage completed until its report exists.

## Finding ledger

Each row records ID, stage/reviewer lens, severity (Blocker/Major/Nit), affected section, claim, source evidence, disposition, proposed edit, owner, human decision and status. Never silently downgrade severity.

- **PROPOSE FIX:** valid criticism with a precise correction. A proposal is not permission to implement.
- **CONTEST:** evidence visible to the reviewer contradicts the finding. Cite file/symbol or recorded decision; "intentional" is not evidence. A comprehension gap generally needs clearer documentation, not a contest.
- **ESCALATE:** resolving the finding needs human knowledge, a product/privacy decision or evidence outside the available record. Keep the gap visible.
- **DECLINE:** a Nit does not justify a change; record why. Do not use this to hide a Blocker/Major or unresolved safety risk.

A completed edit does not automatically close a finding. Recheck it. Reopened issues at a prior fix may mean the fix failed. Preserve accepted trade-offs and their decision source so repeated reviews do not churn them. Stop at the agreed budget or churn and present unresolved issues; do not auto-accept risks to reach a clean report.

## Exit and evidence

Human approval is required for architecture choices and implementation scope. Record approval of an exact design revision, unresolved decisions, accepted risks and permitted first slice. Then use small reviewable PRs and the existing CI/QA/release gates. No merge or release permission follows from a design approval alone.

Measure the pilot using review rounds/time, substantive findings fixed before code, reopened findings, implementation rework and clarification needed by the implementer. No invented baseline, percentage improvement or claim of savings from document volume.

## Source and adaptation

Based on the seven canonical [EGM skills](https://github.com/google/elephant-goldfish-model/tree/main/skills), inspected at upstream revision `0dfb5bf3eebd551d1e805c3ab16cbaa9b1c2c42a` on 2026-11-05. This is an Ate-specific process summary, not installation or execution of upstream instructions. EGM's full review loop uses a five-round cap and two consecutive clean rounds; this pilot deliberately uses a smaller two-round budget with explicit human stop/continue decisions. Upstream bootstrap's broad README generation is not adopted.
