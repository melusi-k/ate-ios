# #535 Export target readiness

## Diagnosis

Failed candidate66c4603973d777c06f05cb077fb7f5f74faafcc4, Account job132914143934, run43747195614, retained artifact14183409935:
https://github.com/melusi-k/ate-ios/actions/runs/43747195614/artifacts/14183409935

CoverageUITests/test32_MoreCollectionsToolsAbout failed351.882s at its unchanged "Export ActivityListView must present" assertion. Its360/480-second allowance had not expired. Immediate post-tap queries completed quickly and reported Settings, not an ActivityListView. This is not the #539 snapshot-print stall pattern.

Inspected original retained pixels: settings-about is at Settings bottom with diagnostics/Privacy/Terms. settings-export-immediately-after-tap is at Settings top, Account & sync/Ate Plus/AI on this device, with no share sheet. Exact synthesized-event record identifies the supposed Export tap at(53.00000055,58.13333326) in a402x874 window, in the upper-left header/logo region, outside the scrollable content band. The paired target snapshot describes the whole application402x874, not an Export button. A correctly targeted Export tap was not established. Do not call this proof that the app's Export action failed.

The old return-to-Tools helper uses only exists/isHittable on a retained lazy target, with whole-app swipes and no final clear-band proof. That permits the observed mis-targeting boundary; its precise XCTest stale-target/scroll-resolution cause remains unknown. The earlier Settings-tab-reset hypothesis is not supported by the actual header tap coordinate and is withdrawn. No app mechanism for resetting scroll was found.

SettingsView.swift, Components.swift (ActivityView/writeTemp) and AppStore+JournalAccountActions.swift are byte-identical main4aa5 to failed#535. AppStore.swift changes only recipe add(clearPendingDraft:), not export. Thus no #535-specific app export mutation is implicated. Retained #532aafed988 test32 passed161.196s and #537 retained test32 passed116.187s, both with ActivityListView in AX. Those are other-candidate passes, not proof this candidate passed or proof of current-main native acceptance.

## Change

Only the final test32 return-to-Export readiness is changed:

- Resolve row as a button with exact settings.export identifier, enabled and fully contained in the live window/Form clear band below the actual Settings navigation bar and above the tab bar/bottom accessory.
- Read geometry twice and require equal row/band frames before readiness. Reject empty/null/infinite geometry and a missing chrome owner.
- Scroll with gestures whose endpoints are inside the measured Settings content band, not whole-app swipes. Retain the original bounded25-earlier/50-later search and2-second existence wait. No additional tap/retry or wait loop is added.
- Retain a pre-tap screenshot and compact row/clear-band geometry receipt. Assert clearance and recheck immediately before the ORIGINAL SINGLE export.tap(). If moved/clipped/unavailable, fail instead of sending an off-band tap.
- Every existing content assertion, ActivityListView presence/nonempty-frame predicate,2-second readiness allowance, screenshot and native360/480 allowance stays unchanged. No app source, export behavior, existing general scrollTo helper, CI selector or workflow is changed.

The new local readiness block is a hypothesis-driven harness fix, not native proof. In particular it must demonstrate the original tap now resolves to the measured button, not an application fallback. The exact inverse reconstructs the entire failed-candidate CoverageUITests.swift byte hash; all prior frozen digests remain unchanged and their assertion-mutant rejection remains active.

## Verification

278Python tests PASS working+fresh depth1; Swift grammar PASS; diff-check PASS. These are source checks, not Apple build/typecheck/XCTest. Original failed-run pixels were inspected; changed readiness pixels and native run remain UNRUN. Reviewer must run test32 on the exact integrated candidate with unchanged budgets, inspect pre-tap row/band and coordinate against the real Tools row, retain ActivityListView evidence, and keep the historical failure as failed. If readiness fails, do not weaken it or lengthen waits. No app correctness claim or universal AX fix is made.
