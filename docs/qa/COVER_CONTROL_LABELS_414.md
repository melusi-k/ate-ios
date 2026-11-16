# #414 normal-text review cover controls

Base: main `4aa5e5ed62c84cba4bb9a9008ae35810956d91ae`.

The fixed HStack compressed three or four cover controls into one row. Text could wrap inside a word. The existing WrapLayout now moves whole controls to another row at their intrinsic widths. Each action has an explicit horizontal fixed-size policy and one-line label. Change photo, Sample cover, optional Generate cover and Remove remain present under exactly their prior conditions, identifiers and handlers. The existing button style already enforces a minimum 44pt target, so no style/target-size change was needed.

This is the normal-text cosmetic follow-up. It does not claim to fix photo generation latency, classification, OCR or its original failure. No existing native case, assertion, input, wait, timeout or workflow was changed.

An additional CoverageUITests extension method checks intact labels, non-overlapping on-screen targets, sample-cover and remove behavior, and retains photo/removed screenshots. Required native selector: `AteUITests/CoverageUITests/testCoverControlsHaveUnbrokenLabelsAndSeparateTargetsAtNormalSize`. Also rerun the unchanged existing `test31_CoverControlsHeroAndTile` and `KeyFlowsQATests/testQA2_AddFromPhoto`. The focused new selector must be explicitly included by Reviewer; this packet does not add CI runner work or change existing selections.

Native compile, UI execution and pixel inspection are **UNRUN**. Reviewer must inspect normal-text iPhone 18 Pro screenshots with all three controls, confirm unbroken labels and working photo/remove targets, and inspect the optional Generate cover layout on a supported device. Source wrapping and accessibility labels alone do not prove the pixels. #414 remains open pending that evidence.

Source PRs close only after the reviewer confirms the destination commit; branches kept.
