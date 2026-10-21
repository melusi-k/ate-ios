### 📋 MVP score — historical snapshot, not current acceptance status

> This file retains the last recorded Tier A/B score snapshot from build 36 for historical context. Tier C was previously undercounted as 6 items; the current checklist contains 67 Tier C IDs. Do not use the historical aggregate as a current release-readiness verdict. Recompute Tier A/B scores only from current evidence and a consistent denominator.

| Tier | Score | % | ✅ | 🟡 | ❌ | ⛔ |
|---|---|---|---|---|---|---|
| Tier A — Must-pass before beta (pilot) | 27 / 44 | 61% | 18 | 18 | 8 | 0 |
| Tier B — Before wider/public launch | 4.5 / 13 | 35% | 2 | 5 | 3 | 3 |
| Tier C — Later polish | 0 / 67 | 0% | 0 | 0 | 67 | 0 |
| **Historical total (build 36 denominator)** | **31.5 / 63** | **50%** | | | | |

| Tier | Category | Score |
|---|---|---|
| A | Recipe creation | 4 / 6 |
| A | Edit / save / delete | 3.5 / 5 |
| A | Auth (launch gate) | 4.5 / 9 |
| A | Sync | 4.5 / 6 |
| A | Share + deep link (launch gate) | 3.5 / 5 |
| A | Timer reliability | 1 / 3 |
| A | Offline | 1.5 / 2 |
| A | Reliability | 0.5 / 2 |
| A | Build/test automation | 3 / 4 |
| A | Real-device smoke test | 0 / 1 |
| A | Pilot readiness | 0.5 / 1 |
| B | Backend/share (launch gate) | 0 / 1 |
| B | Apple account path | 0 / 2 |
| B | Full device QA | 1 / 3 |
| B | Support | 1.5 / 2 |
| B | Monitoring | 0 / 1 |
| B | Privacy/compliance (launch requirement) | 2 / 4 |
| C | Tier C acceptance inventory | 0 / 67 |

Verdict (build 36): pilot candidate, but Tier A isn't green yet. Biggest gaps: real-device validation (auth gate, smoke test, timers in the background), tests not re-run since build 35, web share page on the old backend, and corrupted-store and interrupted-AI recovery. Not public-launch ready.

_Automated by CI (backend-e2e, CoverageUITests, release smoke): A-AUTH-02/06/07, A-SYNC-02/03/06, A-SHARE-03/04(web half)/05, A-CREATE-05, A-CI-03. Results land in qa_results (source='ci') and show next to device results on the Beta screen._
