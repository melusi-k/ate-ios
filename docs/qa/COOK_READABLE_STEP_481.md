# #481 readable long Cook instructions

Base: main `4aa5e5ed62c84cba4bb9a9008ae35810956d91ae`.

Root cause: the normal 30/34pt Cook instruction used `minimumScaleFactor(0.5)`, permitting approximately 15/17pt text when the allotted height was tight.

The instruction now keeps its existing display font, wraps at the viewport width and grows vertically without a scale-to-fit modifier. A vertical ScrollView handles overflow. Short instructions retain the viewport's minimum height. Header, progress, parallel-timer controls, active timer and bottom step controls stay outside the instruction scroll view. Changing the shared step replaces only the scroll identity so the new step starts at its beginning. Existing temperature conversion, full instruction accessibility text, header trait and cookStepText identifier remain.

This is normal-text scope, not a Dynamic Type redesign. It does not change timer behavior, Finish persistence, voice commands, ingredient controls, footer reserve or shared current-step ownership.

A DEBUG + UITesting-only synthetic two-step recipe opens the normal modal Cook route. The new native UI test retains top/end, next-short-step and return-to-start screenshots, checks complete instruction text, and checks that instruction scrolling leaves Next fixed and tappable. The existing shared-step CI selection adds this test and requires its named pass. No wait/timeout/allowance increases or changes to existing native inputs.

Local source tests reconstruct exact parent files and reject missing/duplicated deltas. Native compilation, UI execution and visual readability remain **UNRUN**. Reviewer must inspect those four normal-text iPhone 18 Pro screenshots, confirm text stays at 30/34pt without clipping, confirm the final sentence can be scrolled into view, and check the short step and Back/Next/Finish reachability. AX existence alone does not prove font size or endpoint visibility. Also run existing shared-step and ingredient/timer flows. #481 acceptance stays open until exact-device evidence exists.

Source PRs close only after the reviewer confirms the destination commit; branches kept.
