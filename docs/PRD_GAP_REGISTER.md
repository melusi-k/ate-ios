# PRD gap register

**Status:** working inventory, created 2026-10-12. This is a tracking index, not a claim that every item is currently unimplemented. Each checklist item must be re-verified against current code and evidence before it can be marked done.

**Sources of truth**
- Product requirements: [PRD.md](PRD.md)
- Acceptance inventory: [MVP_CHECKLIST.md](MVP_CHECKLIST.md)
- Scored verification matrix: [QA_MATRIX.md](QA_MATRIX.md)
- Manual/device procedure: [QA.md](QA.md)
- Release gate and current build evidence: [open release-readiness issues](https://github.com/melusi-k/ate-ios/issues?q=is%3Aissue+is%3Aopen+label%3Arelease-readiness)

## Gap ownership / GitHub issues

| Area | Tracking issue | Scope |
|---|---|---|
| Cooking Tracker | [#31](https://github.com/melusi-k/ate-ios/issues/31) | Complete tracker UX, event semantics, history persistence, streak/calendar correctness, tests and accessibility |
| Auth + sync | [#34](https://github.com/melusi-k/ate-ios/issues/34) | Sign-up, confirmation, reset/magic links, session/account lifecycle, two-device sync and conflicts |
| Recipe creation + quality | [#35](https://github.com/melusi-k/ate-ios/issues/35) | URL/social/photo/prompt imports, fallback behavior, draft recovery, recipe quality and duplicate prevention |
| Timers + widgets + Siri | [#36](https://github.com/melusi-k/ate-ios/issues/36) | Timer lifecycle, Live Activities, WidgetKit, App Intents, Lock Screen, Control Center, Siri/Shortcuts |
| Accessibility + UX | [#37](https://github.com/melusi-k/ate-ios/issues/37) | VoiceOver, Dynamic Type, contrast, Reduce Motion, responsive layouts, native navigation and interaction gaps |
| Health + journal | [#38](https://github.com/melusi-k/ate-ios/issues/38) | HealthKit MVP, permission states, insight rules, local journal and journal interaction acceptance |
| Share + security + release gates | [#39](https://github.com/melusi-k/ate-ios/issues/39) | Hosted share browser verification, deep links, Supabase security review, artifact integrity and privacy/legal gates |
| Device QA + support + monitoring | [#40](https://github.com/melusi-k/ate-ios/issues/40) | Physical-device evidence, pilot readiness, support/known issues, monitoring and operational readiness |
| Deferred / future platform work | [#41](https://github.com/melusi-k/ate-ios/issues/41) | StoreKit/Ate Plus, paid-team dependencies, modularization, Watch and other explicitly deferred features |

## Complete acceptance-ID inventory

The IDs below are copied from `docs/MVP_CHECKLIST.md` and grouped by its current sections. The checklist remains the detailed acceptance source; this index ensures areas are not silently omitted from planning.

### Tier A — must pass before beta / pilot

- **Recipe creation:** A-CREATE-01, A-CREATE-02, A-CREATE-03, A-CREATE-04, A-CREATE-05, A-CREATE-06
- **Edit / save / delete:** A-EDIT-01, A-EDIT-02, A-EDIT-03, A-EDIT-04, A-EDIT-05
- **Auth (launch gate):** A-AUTH-01, A-AUTH-02, A-AUTH-03, A-AUTH-04, A-AUTH-05, A-AUTH-06, A-AUTH-07, A-AUTH-08, A-AUTH-09
- **Sync:** A-SYNC-01, A-SYNC-02, A-SYNC-03, A-SYNC-04, A-SYNC-05, A-SYNC-06
- **Share + deep link (launch gate):** A-SHARE-01, A-SHARE-02, A-SHARE-03, A-SHARE-04, A-SHARE-05
- **Timer reliability:** A-TIMER-01, A-TIMER-02, A-TIMER-03
- **Offline:** A-OFF-01, A-OFF-02
- **Reliability / navigation:** A-REL-01, A-NAV-01
- **Build/test automation:** A-CI-01, A-CI-02, A-CI-03, A-CI-04
- **Real-device smoke / pilot readiness:** A-DEV-01, A-LAUNCH-01
- **Apple Health insights:** H-01, H-02, H-03, H-04, H-05, H-06, H-07, H-08
- **Widgets & Intents:** A-WIDGET-01, A-WIDGET-02, A-WIDGET-03, A-WIDGET-04, A-WIDGET-05, A-LOCK-01, A-LOCK-02, A-LOCK-03, A-CONTROL-01, A-CONTROL-02, A-INTENT-01, A-INTENT-02, A-INTENT-03, A-INTENT-04, A-INTENT-05, A-COVER-01
- **Data safety & security:** A-DATA-01, A-DATA-02, A-CI-05, A-CI-06, A-SEC-01, A-SEC-02, A-SEC-03, A-SEC-04, A-SEC-05, A-SEC-06

### Tier B — before wider / public launch

- **Backend/share launch gate:** B-SHARE-01
- **Apple account path:** B-APPLE-01, B-APPLE-02
- **Full device QA:** B-QA-01, B-QA-02, B-QA-03
- **Support:** B-SUP-01, B-SUP-02
- **Monitoring:** B-MON-01
- **Privacy/compliance:** B-PRIV-01, B-PRIV-02, B-PRIV-03, B-PRIV-04

### Tier C — later polish and extended acceptance

- **Polish / architecture:** C-POL-01, C-POL-02, C-POL-03, C-POL-04, C-POL-05, C-POL-06
- **Design review:** C-DES-01, C-DES-02, C-DES-03, C-DES-04, C-DES-05, C-DES-06, C-DES-07
- **Accessibility:** C-AX-01, C-AX-02, C-AX-03, C-AX-04
- **Native acceptance:** C-NAT-01, C-NAT-02, C-NAT-03, C-NAT-04, C-NAT-05, C-NAT-06, C-NAT-07, C-NAT-08, C-NAT-09, C-NAT-10, C-NAT-11, C-NAT-12, C-NAT-13
- **Widgets / Lock Screen / Control Center:** C-WID-01, C-WID-02, C-WID-03, C-WID-04
- **Siri polish:** C-SIRI-01, C-SIRI-02, C-SIRI-03, C-SIRI-04
- **Covers:** C-COV-01, C-COV-02, C-COV-03
- **Journal:** C-JRN-01, C-JRN-02, C-JRN-03, C-JRN-04, C-JRN-05, C-JRN-06, C-JRN-07, C-JRN-08
- **Build 81 fixes:** C-FIX-01, C-FIX-02, C-FIX-03, C-FIX-04, C-FIX-05, C-FIX-06, C-FIX-07, C-FIX-08
- **Recipe quality:** C-AI-01, C-AI-02, C-AI-03
- **Library header:** C-LIB-01
- **iOS 26 tab bar:** C-TAB-01, C-TAB-02, C-TAB-03, C-TAB-04, C-TAB-05, C-TAB-06

> **ID reconciliation note:** The checklist is authoritative. If a prefix in this index differs from the literal ID in the current checklist, fix this register to match the checklist rather than renaming IDs casually. The current checklist has had additions over time and its score summary may lag the individual rows.

## PRD requirements that need explicit decisions / evidence beyond the ID list

- **Cooking Tracker semantics:** The PRD describes Recently cooked via `lastCookedAt`, but a full tracker needs an explicit product decision on whether entering Cook Mode counts as cooking, plus local history, date/time-zone behavior, streak rules and deleted-recipe behavior. Tracked in #31.
- **Universal links:** Paid Apple Developer account, production `ate.app` domain, Associated Domains entitlement and hosted AASA file are external prerequisites.
- **Production security:** Evidence required for RLS, Edge Function auth/input validation/CORS/rate limits, retention/deletion, grants/storage and service-role key containment. Do not change production permissions based on assumptions.
- **Apple Intelligence/device fallback:** Test supported Apple Intelligence hardware, unsupported hardware, and iOS 18/no Foundation Models; confirm provenance badges and offline behavior.
- **Share web flow:** browser smoke test valid slug, unknown slug, and retryable Edge Function outage; verify no PostgREST fallback before changing table grants.
- **StoreKit / Ate Plus:** PRD says planned and not implemented; paid-team / App Store Connect / sandbox dependencies remain external blockers.
- **Apple Journal:** no direct third-party API to write into Apple Journal; only the explicitly documented picker and future Health donation possibilities are in scope.
- **Module boundaries:** modularization is a planned risk-reduction project, not a release prerequisite unless explicitly promoted.
- **Real-device evidence:** simulator CI does not satisfy device-only acceptance for auth, sync conflicts, timers, Live Activities, Health permissions, widgets, rotation, accessibility and release artifact installation.

## Working rules

1. A requirement is not complete because code exists; link a passing test, artifact, or device evidence.
2. Keep launch blockers separate from later polish and external dependencies.
3. Update the relevant issue and this register when scope/status changes.
4. Do not close release blockers or approve a release while required checks are running, inconclusive, or failing.
5. Avoid duplicate issues: add new evidence and subtasks to the matching area issue unless a distinct ownerable unit of work is needed.
