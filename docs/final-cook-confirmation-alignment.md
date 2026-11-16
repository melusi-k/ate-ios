# Final-step Finish test: acknowledge the saved-cook confirmation

Base: #534 `bc45b9588799da4eb1c603eb9e6dfe28e5918ed4`.
Branch-only test alignment. Native execution remains UNRUN.

In native Account run 43694805899, test06b_CookModeFinalStepAndFinish reaches
Step 4, confirms Next is absent, checks Finish's label, and taps Finish at
30.11s. Its failure is the subsequent Cook-mode button expectation, not a
missing final step or Finish button. The separate following test then fails
to terminate the same PID. This patch does not claim to fix that termination
failure or the Journal-tab-hittable failure.

CookModeView.finish queues the event, records it, clears the matching session
and calls complete. complete always sets reflectionOffer to that event.
The sheet shows the saved-cook confirmation, including
cookCompletion.recorded and the Done button cookReflection.notNow.
CookModeView's reflection-offer onDismiss is the single exit owner. Therefore
Finish alone does not immediately expose the underlying Cook-mode button.

The existing testCookModeCompletionRecordsCookingDay already follows this
user flow. test06b is now aligned to it: after Finish, wait for the recorded
confirmation, wait for exactly one Done button, tap Done, then retain the
original Cook-mode arrival assertion verbatim. Every original test action,
final-step check, Finish label assertion and timeout is retained. No retries,
longer waits, product edits or automatic dismissal are added.

The new source contract strips only these five added lines and reconstructs
the entire original AteUITests.swift byte for byte. This is not a native pass.
The reviewer must run the original Account gate, including the real finish,
completion-history, termination and Journal cases. Those remain separate
open checks until current-head evidence qualifies them. No waiver, merge,
publication or PR closure is included. Source PRs close only after the
reviewer confirms the destination commit; branches kept.

Native source:
https://github.com/melusi-k/ate-ios/actions/runs/43694805899/artifacts/14157323576
