# #157 proven navigation preconditions, not broad assertion rewrites

Incremental on shared-Cook c0a459e (prior Finish25f4451 beneath). No publishing.

Read exact historical CoverageUITests.swift4912b086 from GitHub and the actual
Coverage artifact, not line-number guesses.

- Backend-down test failed at Account & sync. Retry/error/local retained card had
  already passed. Log shows a sheet swipe followed by Library and Settings taps
  with computed hit point(-1,-1). Current Add explicitly disables unsaved swipe
  dismissal. Test now uses Cancel/Discard and requires actual Add disappearance
  before existing Library/account/sync assertions. No error/library assertion is
  removed or relabelled passing. This follows user-visible draft retention.
- Settings-back test expects lazy Beta & diagnostics at initial Form load even
  though current source puts it below everyday settings. Reveal with existing
  bounded scroll helper, then retain original existence/back/return assertions
  and add hittability before tap. No global helper/test allowance increase.
- Journal original was duplicate Image+StaticText sharing insights.entryMomentContext,
  not a timeout. Current route is Journal entry -> detail.momentContext with
  firstMatch; source changed. No additional selector patch without current proof.
- Health empty->sample original really failed to show Recovery day after sample
  action; model uses current sample scenario/refresh code and existing fixture
  units. No speculative sleep/label/test change. Need current native output.
- Health sheet original opened/reopened successfully then Done remained after
  swipe. Do not relabel as failed open or weaken its dismissal assertion. Need
  current native screenshot/gesture outcome before a product/harness change.

Original artifact:
https://github.com/melusi-k/ate-ios/actions/runs/39710638199/artifacts/12397946788
Historical exact source read ref4912b086af0935d3c28972f8e7236447655aa58f.
Later42610132681 focused logs contain none of the six original named methods.

Python185PASS/diffcheckPASS only. Native/device/pixels NOT RUN. Six methods/full
Coverage shard remain open until exact-current-candidate execution. Existing
unchanged testBottomBarsDoNotOverlapRecipeDetail is selected in prior Cook packet;
this increment does not dispatch or add runners. No production Journal activation.
