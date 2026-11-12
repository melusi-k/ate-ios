# Optional iPhone Duo screenshots

Manual, non-gating exploration approved in [Discussion #492](https://github.com/melusi-k/ate-ios/discussions/492). The iPhone 18 Pro / iOS 27.0 gate and its strict selector stay unchanged. No layout work is included; layout changes wait until after the pilot and #430's continuity proof.

After the workflow is published, use Actions > Duo exploration (manual, non-gating) > Run workflow and select the intended branch. There is no push, PR or scheduled trigger. It uses the existing `xcode-27` macOS runner label and Xcode 27.1, not a paid/larger runner. A separate strict selector requires iPhone Duo / iOS 27.1 and fails with its inventory if absent. It will not fall back to the gate device or silently download another runtime.

The run builds exact `github.sha` into dedicated DerivedData, boots the selected simulator, then runs only `DuoExplorationUITests`. The dedicated xctestrun sets `ATE_DUO_EXPLORATION=1` for AteUITests. Outside that opt-in these cases explicitly skip, never count as Duo acceptance. Root uses normal UI-testing startup; Cook Mode uses the existing isolated one-step `-qaCookJournalHost` fixture in both modal and pushed hosts. This is synthetic UI evidence, not a normal-user recipe/model or full cooking-flow test.

Retained evidence: source SHA, Xcode/runtime/device inventory, selected UDID, build/boot/test logs, xcresult, exported screenshot attachments and failure screenshots where available. Inspect the artifact `duo-exploration-<run>-<attempt>` and compare root chrome and Cook Mode controls in portrait/landscape. Report actual pixels and failures honestly. A successful job only means the named capture cases ran, not visual approval or a gate pass.

Portrait/landscape orientation is not folded/open/partially folded posture testing. No posture transitions, step-resume continuity, hinge geometry, widgets or Live Activities are asserted. Those remain in [#430](https://github.com/melusi-k/ate-ios/issues/430) and require their own evidence; the Duo simulator's extension limits are recorded in #492. No new CI run, screenshot result or layout-readiness claim is earned merely by adding this workflow.
