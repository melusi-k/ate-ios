# Ate Intelligence Foundation: design-review pilot

Status: Proposed discovery/design document, not approved architecture or implementation.
Owning initiative: [#316](https://github.com/melusi-k/ate-ios/issues/316).
Baseline: main `351c7f18170272112dfaf1a609b8519c31205008`, inspected 2026-11-05.
Engineering/review owners: To confirm. No delivery date, implementation branch or release gate is committed.

## Problem and goal

Ate already exposes system actions and uses on-device models in separate features. The problem is inconsistent reusable boundaries and evidence, not a missing generic chatbot. The proposed outcome is useful existing actions and assistance with scoped, permitted context and user control. Issue #316 retains the product outcome, workstreams, acceptance and sequencing authority. Current release-readiness and product-foundation work remain ahead of this initiative.

This is the first pilot of [the design review process](../DESIGN_REVIEW.md). Its immediate goal is a reviewable architecture baseline and explicit decisions, not a user-facing AI launch. No targets or usefulness baseline have been measured. No external provider, user-content telemetry, autonomous actions, new paid resources, data migration or broad context access is authorized.

## Current implementation, not acceptance proof

| Boundary | Existing source and contract | Implication / evidence limit |
| --- | --- | --- |
| System actions | `Ate/Intents/AteAppIntents.swift`: existing recipe entities, lookup and actions. `Ate/Services/WidgetBridge.swift`: system bridges. Existing intent QA rows/tests. | Audit each action's domain invocation and confirmation; declaration is not Siri/device proof. Open Siri work is not merged merely because an issue references it. |
| Recipe generation | `Ate/Services/OnDeviceBackend.swift`: availability inspection, Foundation Models generation and backend fallback. | Reuse existing backend boundary and validators before inventing another generation stack. Map session, cancellation and provenance before extraction. |
| Reflective prompts | `Ate/Services/JournalSuggestionService.swift`: bounded Foundation Models prompt path and local template fallback. | Preserve local-only Journal behavior; model use is not permission to add Journal text to a general context provider. |
| Recipe progress insight | `Ate/Views/InsightsView.swift`, `RecipeProgressInsightService` model/fallback path. | Separate use case with its own input/evidence; no shared context-service implementation proven. |
| Journal/meal persistence | `JournalStore`, `JournalOpenState`, `FoodJournalStore` and `FoodJournalMigration`. | Recovery, local-only privacy and typed identity are existing boundaries, not optional future design. Historical Food Journal baseline has drift: see report. |
| Diary/history consumers | `NutritionDiaryRepository`, `CookingHistory`; Insights directly reads diary/history/Journal paths. | A proposed context provider must not bless existing singleton/default-domain reads as safe account-bound access. Resolve active ownership work before integration. |
| AI validation | `docs/CI.md`; three distinct lanes. | Standard mocks/unavailable-state tests, same-device eligible real inference, and physical-device quality remain separate. Hosted model readiness is not proven. |

This is a bounded map, not the complete per-intent capability register. The [drift report](../reviews/2026-11-05_DESIGN_DRIFT.md) records two concrete historical-contract differences and the missing shared design. No native test, real inference or device acceptance was run for this document.

## Candidate critical journeys

1. Given an existing saved recipe and a permitted supported system surface, when the user requests an existing read/open action, then identity lookup and authorization resolve through the same domain contract as the app. Deleted, ambiguous, private and unavailable records produce honest outcomes without returning another scope's content.
2. Given a selected future assistance capability, when the model is unavailable, disabled, not ready, timed out or cancelled, then its documented safe fallback or failure appears without silently applying generated state. This is an architecture requirement, not an approved use-case selection.
3. Given Journal or Health data that the selected capability has not been permitted to use, when context is requested, then it is excluded. No broad `getEverything()` access or direct model-to-persistence path is proposed.

## Architecture direction for review

Keep deterministic execution separate from generated suggestions:

`User/system request -> action authorization/policy -> purpose-scoped context -> model or deterministic service -> typed validation -> user review/confirmation where consequential -> canonical domain operation -> truthful result`

This is a proposed flow, not a claim these shared modules already exist. A read-only action may not need a model, context aggregation or a mutation step. Keep that path simple.

Proposed boundaries, names not yet committed:

- Action adapters resolve identities and express intent, but do not duplicate persistence/business rules.
- Purpose-specific context providers return bounded typed snapshots, provenance, age and scope. No SwiftData handle is exposed to a model. Missing/corrupt data is unavailable, not empty or fabricated.
- A reusable model boundary represents runtime availability, cancellation, timeout, failure, fallback and typed output validation. Adapt existing call sites incrementally after parity tests.
- Canonical domain services validate and execute writes with current user confirmation and ownership rules. Generation does not authorize execution.
- Governance records capability-specific context, consent/control, model/device requirements, fallback, tests and evidence limits. Diagnostics exclude prompts and personal content.

## Alternatives to decide

| Option | Benefit | Risk / reason not yet selected |
| --- | --- | --- |
| Harden each existing feature without a shared platform | Smallest first diff; avoids speculative abstraction. | Policy/session duplication may remain; could be the right first slice if only one capability needs change. |
| Extract small shared contracts only for one chosen capability | Tests actual reuse while retaining domain ownership. | Needs an approved first problem and demonstrated parity; for discussion. |
| Build a generic assistant with broad context immediately | Broad apparent capability. | Violates scoped-data and incremental-delivery direction; outside current initiative scope. |

Do not select the first vertical slice on behalf of the owner. Issue #316 candidates remain proposals. Stage 0 must settle the user problem, owners, privacy scope and evaluation before implementation planning.

## Safety and failure contracts to specify

- Preserve local Journal/Health permission boundaries, source provenance and opt-out/Private Mode semantics.
- Bind context and actions to the active canonical domain; account changes, reset and cancellation invalidate stale work.
- Bound query size, prompt input, retries and model execution; define each limit after inspecting current behavior, not by inventing numeric defaults.
- Validate generated structure and domain constraints before user review or execution; never overwrite original content silently.
- Handle unavailable runtime, malformed output, deleted/stale records, corruption, interrupted requests and cancellation explicitly.
- No remote processing or telemetry expansion. Any proposed exception needs separate privacy/security/product decisions.
- Follow current migration, recovery, export and deletion contracts. D2 in the drift report requires a decision, not silent normalization of the docs.

## Discovery plan and future file boundaries

These are proposed documentation/discovery steps only:

1. Complete per-action inventory from `AteAppIntents.swift`, `WidgetBridge.swift`, owning domain services and existing QA rows. Record side effects, confirmation, private/offline/stale identity behavior and device proof missing.
2. Complete model call-site inventory from the three paths above, their validators/tests and `docs/CI.md`. Map input scope, sessions, cancellation, fallback and provenance.
3. Resolve Journal/diary ownership and the drift findings against current release work. Do not create parallel ownership or migration code.
4. Draft focused ADRs only for settled questions: scoped context contract, model lifecycle, permission/control and evaluation/rollout. ADRs are not marked accepted without a human decision.
5. After the first slice is approved, refine this into a file-by-file implementation plan, incremental PR sequence and test contract. None is implementation-ready today.

No Swift change list is fabricated before that selection. Expected documentation additions are this architecture map and, when decisions exist, focused ADRs alongside it. Reuse issue #316, the QA matrix and lifecycle evidence rather than copy their acceptance lists here.

## Evaluation and rollout boundaries

Deterministic negative-scope/authorization/identity/output-validation/fallback tests must preserve current journeys. Real-model evaluation requires actual eligible-device inference and versioned fixtures, exact SHA/build/device/OS and human rubric. Physical-device Siri/system-surface and model quality remain distinct from simulator automation. No source inspection or green mock test qualifies usefulness or release.

Pilot cohort/channel, stop conditions, baseline, observation window, privacy-safe signals, support owner and expansion decision remain open. No deployment or model-lane dispatch is requested by this document.

## Review state

Five-stage design review: Not run. No finding is closed or risk accepted by this document. Budget for this initial documentation pilot: up to two review rounds, then stop with unresolved decisions for the owner. Selected lenses: simplicity, comprehension, privacy/data integrity and implementation readiness.

| ID | Decision needed | Owner/status |
| --- | --- | --- |
| IF-01 | First user problem and vertical slice | Product owner, pending |
| IF-02 | Engineering/privacy/security review ownership | To confirm |
| IF-03 | Purpose-specific data permissions and context ownership | Pending audit and review |
| IF-04 | Session/runtime/fallback contract and current parity evidence | Pending |
| IF-05 | Versioned evaluation, baseline and supported device matrix | Pending |
| IF-06 | Drift D2: contract versus legacy-key retirement | Human decision required |

Human approval of a named design revision and scope is required before implementation. The Product Lifecycle human decision, exact-candidate evidence and existing release gates remain in force. This document does not authorize merging.
