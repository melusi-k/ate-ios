### 📋 MVP score (tiered — [MVP_CHECKLIST.md](https://github.com/melusi-k/ate-ios/blob/main/docs/MVP_CHECKLIST.md) · [QA_MATRIX.md](https://github.com/melusi-k/ate-ios/blob/main/docs/QA_MATRIX.md))

| Tier | Score | % | ✅ | 🟡 | ❌ | ⛔ |
|---|---|---|---|---|---|---|
| Tier A — Must-pass before beta (pilot) | 19.5 / 44 | 44% | 8 | 23 | 11 | 2 |
| Tier B — Before wider/public launch | 4.5 / 13 | 35% | 2 | 5 | 3 | 3 |
| Tier C — Later polish | 0 / 6 | 0% | 0 | 0 | 6 | 0 |
| **Total** | **24 / 63** | **38%** | | | | |

| Tier | Category | Score |
|---|---|---|
| A | Recipe creation | 3 / 6 |
| A | Edit / save / delete | 3.5 / 5 |
| A | Auth (launch gate) | 2.5 / 9 |
| A | Sync | 3 / 6 |
| A | Share + deep link (launch gate) | 2 / 5 |
| A | Timer reliability | 1 / 3 |
| A | Offline | 1.5 / 2 |
| A | Reliability | 0.5 / 2 |
| A | Build/test automation | 2 / 4 |
| A | Real-device smoke test | 0 / 1 |
| A | Pilot readiness | 0.5 / 1 |
| B | Backend/share (launch gate) | 0 / 1 |
| B | Apple account path | 0 / 2 |
| B | Full device QA | 1 / 3 |
| B | Support | 1.5 / 2 |
| B | Monitoring | 0 / 1 |
| B | Privacy/compliance (launch requirement) | 2 / 4 |
| C | Polish | 0 / 6 |

Verdict (build 36): pilot candidate, but Tier A isn't green yet. Biggest gaps: real-device validation (auth gate, smoke test, timers in the background), tests not re-run since build 35, web share page on the old backend, and corrupted-store and interrupted-AI recovery. Not public-launch ready.
