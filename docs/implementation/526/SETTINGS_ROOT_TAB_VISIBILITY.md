# Settings keeps root tabs discoverable

Exact base3a0b1afa61a65bab8f5527fa2e5a9f4fdfca725c, Compile43359138003 account job131668348420.

Caller: CoverageUITests.testNavigationHeadersRemainStableOnShoppingAndSettings fails at shared helper CoverageUITests.swift:76. This is not a Cook completion or pushed Journal back-button failure. In the retained trace Shopping switches to Settings26.51s; Settings header exists35.67s after scrolling; Settings selection is confirmed36.47s. The deliberate reverse Form gesture occurs39.52-40.40s; screenshot42.90s; Journal tab stays absent43-48s. Failure50.034s. Existing screenshot title saying revealed is not evidence that it actually was.

Source applies onScrollDown minimization globally on modern tabs. Narrow product repair: .never while Settings is selected, .onScrollDown elsewhere. Settings is a root switchboard and its scroll must not strand the user in selected-only chrome. Conditional policy changes the existing native TabView modifier, not the TabView identity or stack contents. No polling, delayed reveal, extra gesture, forced selection, back fallback or navigation reset.

Existing test/assertions/gestures/waits and CI budgets are unchanged. Added a stricter native journey: scroll Settings down, require exactly one hittable Journal tab immediately without reverse gesture, tap once and verify Journal root/selection. Native test, compile and actual pixels UNRUN here. Reviewer must run this new test and unchanged header test, inspect retained screenshot, and verify other root tabs still minimize normally and can be restored. No claim of native pass before that qualification.

Compared #522 exact99731deb and #526 exact3a0b1afa: modern tab minimization source is unchanged; failure is grounded in same-run actual selection/header/gesture sequence, not an invented new regression. No older passing execution of this exact header sequence was supplied. Full navigation-header-tests.log is not embedded in job output; additional AX/pixels may refine diagnosis, but global minimization plus repeated absent root destination is enough for this bounded Settings-only policy candidate.

Branch-only; Reviewer publishes/merges. Source PR closes only after destination commit confirmed; branches kept. Activation OFF.
