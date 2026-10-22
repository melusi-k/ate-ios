# Ate unified product backlog

**Status:** migration in progress, 22 October 2026  
**Purpose:** one product backlog, organised by feature area. Release commitments and delivery priority are separate classifications; Tier A/B/C are no longer the working backlog taxonomy.

## Source of truth

- **This document** is the navigation/index for the unified issue backlog and its classification rules.
- [MVP_CHECKLIST.md](MVP_CHECKLIST.md) remains the source for stable acceptance IDs and acceptance definitions.
- [QA_MATRIX.md](QA_MATRIX.md) remains the source for per-ID verification results and evidence.
- [MVP_SCORE.md](MVP_SCORE.md) is historical until its score is recomputed from current, exact evidence.
- Each linked GitHub issue remains the owner for implementation and its acceptance criteria. Do not copy a feature's implementation checklist into this index.

## How to classify work

Every issue and pull request should have exactly one label from each family:

| Dimension | Labels | Meaning |
|---|---|---|
| Feature area | `area:recipes`, `area:library-discovery`, `area:cooking-timers-widgets`, `area:accessibility-navigation`, `area:health-journal`, `area:shopping-settings`, `area:sharing-security-reliability`, `area:future-platforms`, `area:product-infrastructure` | Where the work belongs |
| Release gate | `gate:pilot`, `gate:public-launch`, `gate:uncommitted` | The earliest committed release gate for the issue; not a completion status |
| Priority | `priority:p0`, `priority:p1`, `priority:p2`, `priority:p3` | Delivery urgency independent of release gate |

### Priority definitions

- **P0 — Critical:** actively blocks core use or a committed release, or presents a material security/data-integrity risk.
- **P1 — High:** important core flow, release readiness, or cross-feature defect; schedule ahead of normal backlog work.
- **P2 — Normal:** meaningful improvement or verification gap without a confirmed immediate release block.
- **P3 — Later:** explicitly deferred/platform-expansion work with no committed release date.

Do not derive priority solely from a former tier label. Review priority when user impact, dependencies, release decisions, or evidence changes.

### Release-gate rules

- **Pilot:** preserves work already committed as a pilot/internal-beta requirement, including existing Tier A acceptance.
- **Public launch:** preserves requirements explicitly committed for wider/public launch, including existing Tier B acceptance.
- **No committed release gate:** work not currently tied to a committed launch gate, including explicitly deferred work. It is not synonymous with unimportant.
- Former Tier C items are not automatically low priority. Accessibility, reliability, or other work can be promoted by an explicit product decision; do not silently change an existing release commitment.
- When an issue spans several acceptance IDs with different gates, its issue label represents the **earliest committed gate**. Each acceptance ID keeps its own original ID and evidence; the issue body should call out mixed-gate scope.

## Unified backlog by feature area

Issue-level classifications below are reflected in GitHub labels. The issue tracker remains authoritative for current state, owner, implementation progress, and evidence.

### Recipe creation and quality

- [#35 — Recipe creation, import fallback, and recipe-quality gaps](https://github.com/melusi-k/ate-ios/issues/35) — Pilot · P1
- [#89 — On-device generation, prompt quality, and interrupted-generation retry](https://github.com/melusi-k/ate-ios/issues/89) — Pilot · P1

Acceptance families include recipe import, photo/prompt generation, edit/save correctness, interrupted generation, fallback behavior, and recipe-quality edge cases.

### Library and discovery

- [#73 — Library browsing, search, filters, collections, sorting and reorder](https://github.com/melusi-k/ate-ios/issues/73) — Pilot · P1
- [#101 — Expandable recipe-detail sheet](https://github.com/melusi-k/ate-ios/issues/101) — Pilot · P1
- [#85 — HomeView design from device feedback](https://github.com/melusi-k/ate-ios/issues/85) — No committed release gate · P2

### Cooking, timers and widgets

- [#31 — Cooking Tracker and cooking-history feature](https://github.com/melusi-k/ate-ios/issues/31) — Pilot · P1
- [#36 — Timers, Live Activities, widgets, intents, Siri/Shortcuts](https://github.com/melusi-k/ate-ios/issues/36) — Pilot · P1
- [#60 — Cooking Tracker physical-device acceptance follow-up](https://github.com/melusi-k/ate-ios/issues/60) — No committed release gate · P2

Simulator/CI acceptance and physical-device acceptance remain separate. A green simulator result does not satisfy a device-only requirement.

### Accessibility and navigation

- [#37 — Accessibility, responsive layout, and native interaction gaps](https://github.com/melusi-k/ate-ios/issues/37) — Pilot · P1
- [#68 — Top navigation bar and screen headers](https://github.com/melusi-k/ate-ios/issues/68) — Pilot · P1
- [#69 — Bottom tab bar and tab-state behavior](https://github.com/melusi-k/ate-ios/issues/69) — Pilot · P1
- [#83 — Native sheets for Explore destinations](https://github.com/melusi-k/ate-ios/issues/83) — Pilot · P1

### Health and journal

- [#67 — Deferred device and Health entitlement acceptance](https://github.com/melusi-k/ate-ios/issues/67) — No committed release gate · P2
- [#84 — Foundation Models-powered recipe and progress insights](https://github.com/melusi-k/ate-ios/issues/84) — No committed release gate · P2

Journal implementation/automated acceptance and Health entitlement/device evidence must remain separately classified and evidenced.

### Shopping List and Settings

- [#72 — Shopping List workflows, persistence, aisle grouping and sharing](https://github.com/melusi-k/ate-ios/issues/72) — Pilot · P1
- [#74 — Settings, preferences, data tools and beta-channel safety](https://github.com/melusi-k/ate-ios/issues/74) — Pilot · P1
- [#145 — Settings empty-row cleanup and dynamic About build notes](https://github.com/melusi-k/ate-ios/issues/145) — No committed release gate · P2

### Sharing, security and reliability

- [#34 — Authentication, account lifecycle, and sync gaps](https://github.com/melusi-k/ate-ios/issues/34) — Pilot · P0
- [#39 — Hosted sharing, production security review, and release blockers](https://github.com/melusi-k/ate-ios/issues/39) — Pilot · P0
- [#82 — On-device UI and sharing regressions](https://github.com/melusi-k/ate-ios/issues/82) — Pilot · P1
- [#106 — App Clip discovery](https://github.com/melusi-k/ate-ios/issues/106) — No committed release gate · P2
- [#107 — Isolated App Clip shared-recipe viewer](https://github.com/melusi-k/ate-ios/issues/107) — No committed release gate · P2

### Future platform work

- [#41 — StoreKit/Ate Plus, modularization, and deferred platform features](https://github.com/melusi-k/ate-ios/issues/41) — No committed release gate · P3
- [#86 — Platform support for watchOS, iPadOS, tvOS and visionOS](https://github.com/melusi-k/ate-ios/issues/86) — No committed release gate · P3
- [#87 — CarPlay recipe and active-timer support](https://github.com/melusi-k/ate-ios/issues/87) — No committed release gate · P3

### Product infrastructure and delivery

- [#30 — Release readiness follow-up](https://github.com/melusi-k/ate-ios/issues/30) — Pilot · P0
- [#33 — Internal-beta release readiness record](https://github.com/melusi-k/ate-ios/issues/33) — Pilot · P0
- [#40 — Beta support, monitoring, rollout, and device validation](https://github.com/melusi-k/ate-ios/issues/40) — Public launch · P1
- [#45 — Ate Release Ready](https://github.com/melusi-k/ate-ios/issues/45) — Pilot · P0
- [#70 — Requirements, checklist, QA matrix and ownership reconciliation](https://github.com/melusi-k/ate-ios/issues/70) — No committed release gate · P1
- [#76 — Repair flaky account-sync UI assertion](https://github.com/melusi-k/ate-ios/issues/76) — Pilot · P1
- [#78 — CI/workflow operations and test-gate policy](https://github.com/melusi-k/ate-ios/issues/78) — No committed release gate · P2
- [#79 — Feature verification campaign](https://github.com/melusi-k/ate-ios/issues/79) — Pilot · P1
- [#115 — Remaining Xcode warnings](https://github.com/melusi-k/ate-ios/issues/115) — No committed release gate · P2
- [#135 — App-wide regression suite and evidence](https://github.com/melusi-k/ate-ios/issues/135) — Pilot · P1
- [#138 — CI resilience and regression-test execution audit](https://github.com/melusi-k/ate-ios/issues/138) — No committed release gate · P2

## Acceptance-ID migration policy

1. Preserve every existing A-*, B-*, and C-* acceptance ID. IDs are stable references, not backlog tiers.
2. Reorganise the working backlog by feature area and retain a separate release-gate field for each requirement.
3. Use the owning issue's priority label as the initial issue-level priority. Where an issue contains materially different priorities, split the work or document the exception rather than pretending one label describes every task.
4. Keep implementation status and verification status distinct: not started, in progress, implemented, deferred versus not run, automated pass, manual/device pass, blocked, or failed.
5. Every verification claim must link to the exact commit/run/test or manual/device evidence. Test source presence, an enabled accessibility setting, a successful build, and a non-blocking workflow are not acceptance evidence by themselves.
6. Keep historical Tier A/B/C scores clearly marked as historical until the full acceptance inventory is re-scored from current evidence. Do not convert the migration itself into a pass or alter an existing release gate without an explicit product decision.

## Migration checklist

- [x] Automatic labels for feature area, release gate and priority added to issue/PR forms and GitHub Actions.
- [x] Retrospective classification applied to currently open feature, delivery and release-readiness issues.
- [x] Open PRs classified using the same label families.
- [ ] Reconcile every acceptance ID against its area, original commitment, owning issue, current test and current evidence.
- [ ] Update checklist and QA matrix presentation to group acceptance IDs by feature area rather than by Tier A/B/C.
- [ ] Replace tier-based aggregate score presentation only after current evidence has been reconciled and the scoring denominator is validated.
- [ ] Validate that the generated in-app Beta checklist and ID consistency checks remain in sync after the documentation migration.
