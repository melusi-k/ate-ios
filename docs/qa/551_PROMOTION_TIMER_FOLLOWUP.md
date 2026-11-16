# Cook golden matrix follow-up

Base hosted73b1f95605897cabc9a508c426ea658e28ac440c, failed run evidence artifact14196577393. No claim that matrix qualified.

## Diagnosis

Original BottomBars regression starts timer34.09s, synthesis34.47s, idle wait34.81s, missing-idle notification94.90s. Exceeds180s, resumes186.98s and attaches detail-bottom-bars198.10s, but exported raw manifest has no screenshot for that failed test. No assertion occurs before cap. This is XCTest idle synchronization after real timer start, not live base64 output. No stack/unified trace in packet establishes whether continuous timer activity, system wait or actual app busy work caused it. A source timer optimization is not grounded.

## Capture correction

Keep .presentationContentInteraction(.resizes) unchanged. Medium initial capture precedes swipe and requires Expand fully. After swipe, assert Expand fully disappears, labeling the captures promoted-large-midscroll/finalAsk. Never claim sustained-medium scrolling. No product presentation change.

## Additive timer layout proof

New explicit DEBUG + UITesting-only -qaCookGoldenRunningTimer route sets a deterministic recipe, starts its real600s timer through TimerCenter.start and pushes the actual RecipeDetailView. Does not pause/freeze timers, disable idle synchronization or alter timer implementation. Dedicated opt-in test asserts the actual running-timer Pause control, left value, one timer bar, offline banner/top geometry, floating Cook clearance and final Ask clearance. Captures running-timer-bottom-bars and running-timer-finalAsk. This proves layout with an already-running timer only; it is NOT proof of the Start timer tap, timer alert performance or whole timer lifecycle. Startup may still hit the same idle failure: native is required.

Original CoverageUITests regression remains byte-unchanged AND selected and required to PASS, with its original detail-bottom-bars capture requirement. Matrix now8 selectors/15 captures. No failure is skipped or converted to acceptance. Existing180/240 budgets remain. New route no-op without both explicit flags; no release route.

Native/typecheck/pixels UNRUN. Qualification requires exact hosted head: all8 named passes and15 decoded inspected captures, especially medium before promotion, promoted-large after, running timer + finalAsk, and original timer-start regression. If original still stalls, report only additive layout observations and preserve failed overall qualification.

Source PRs close only after reviewer confirms destination commit; branches kept.
